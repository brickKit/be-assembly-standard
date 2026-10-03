[English](../../en/04-foundations/19-background-jobs.md) · [中文](19-background-jobs.md)

# 后台任务

不由请求触发的工作怎么声明、调度、监督和观测，并且在每种语言里、单跑和外壳两种形态下都一样。读者是要写周期循环、夜间任务、重试或异步命令的人。

## 范围

组件内所有不代表某个入站请求执行的工作：

- 周期循环（outbox 推送泵、过期预留的清扫）；
- 同一时间只能在一处运行的工作（分区维护、数据生命周期冻结、快照回填）；
- 绑定时间槽的工作（日报、第四季度"开下一个会计年度"的提醒）；
- 在业务事务里入队的异步命令（开异常待办、回查投递结果、重试补偿）。

不在本文：消费事件（[12-event-bus.md](12-event-bus.md)）；推进卡住的跨组件流程的 reconciler，它建在这些任务之上（[11-consistency-across-components.md](11-consistency-across-components.md)）；跨天、多人参与的长流程，是否引入工作流引擎在同一篇里评估。

## 选择

- **一个 Jobs 端口，归 SDK 所有，四种类型**：`every`、`singleton`、`cron`、`queue`。
- **一处声明。** 模块在一份声明（一个文件）里列出它的全部任务和 worker；它的启动钩子只做一次性初始化，绝不起循环。
- **由 SDK 监督。** 任务出错或 panic 时记日志、计数、按退避重启；一个任务停下不影响别的任务；单跑和外壳行为相同。
- **状态放在组件自己的 schema 里**，是 SDK 平台迁移建的三张表。同一个组件的单跑实例和外壳实例同时在跑时，靠同一批行互相协调。
- **不用 Kubernetes CronJob，不用 `pg_cron`，不用外部调度器。** 一个要经测量才成立的例外：对进程来说太重的任务，还可以经可选的 **"跑一次"入口**以独立进程运行、由外部触发；它抢的是同一批租约和时间槽行，所以仍然只跑一次（见[端口契约](#端口契约)）。

**状态**：已定；随 3.0.0 统一升级落地。今天有十二个组件各带一份手抄的循环（十二份分区包，各有各的定时器）；外壳里成员的循环失败后就一直停着，单跑时则是进程退出、被平台重启。Jobs 端口替换掉它们全部。brickKit 不做平台级定时任务（FR06-007：Docker 和 Podman 上没有常驻的调度者，只在 Kubernetes 上生效的字段会让同一份 `component.yaml` 在两种目标上行为不同）；它的答复引用 [0508](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md) 作为推荐做法，并为少见的重任务建议了下面的"跑一次"入口。

## 端口契约

契约是表和行为，这样每个 SDK、不论哪种语言，实现的都是同一件事（组件协议，[02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)）。

**声明。** 一个任务有：在本组件内唯一的名字（指标、租约、日志都用它）、类型、间隔（`every`、`singleton`）或时间表（`cron`）、单次运行的超时。`cron` 的时间表要么是五段式 cron 表达式（`0 2 * * *`），要么是 `@every <duration>`（`@every 2s`）。消费入队作业的 worker 有：类型名、并发数、最大尝试次数、退避列表，以及尝试用尽时的处理函数。

**覆盖。** `JOBS_OVERRIDES`（按任务名作键的 JSON，包括运行时自带的 `be.*` 任务）按部署覆盖任务的 `interval`、`cron` 或 `enabled`；写了不存在的任务名时记一条 WARN 日志并忽略（be-protocol P14.5）。

**表**（在组件自己的 schema 里；组件不为它们写 DDL）：

```sql
CREATE TABLE besdk_job_lease (
    name       TEXT PRIMARY KEY,
    holder     TEXT        NOT NULL,   -- <组件 ID>/<实例 id>
    epoch      BIGINT      NOT NULL DEFAULT 0,   -- 防护令牌，每次接管 +1
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE besdk_job_slot (
    name       TEXT        NOT NULL,
    slot_at    TIMESTAMPTZ NOT NULL,   -- 这个时间槽的计划时刻
    holder     TEXT        NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    done_at    TIMESTAMPTZ,
    result     TEXT,
    PRIMARY KEY (name, slot_at)
);
CREATE TABLE besdk_job_queue (
    id           UUID        PRIMARY KEY,              -- UUIDv7
    kind         TEXT        NOT NULL,
    args         JSONB       NOT NULL,
    unique_key   TEXT,                                 -- 可选的去重键
    run_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts     INT         NOT NULL DEFAULT 0,
    max_attempts INT         NOT NULL,
    state        TEXT        NOT NULL DEFAULT 'ready', -- ready | running | done | dead
    lease_until  TIMESTAMPTZ,
    last_error   TEXT        NOT NULL DEFAULT '',
    traceparent  TEXT        NOT NULL DEFAULT '',
    causation_id TEXT        NOT NULL DEFAULT '',
    hop_count    INT         NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at  TIMESTAMPTZ
);
CREATE UNIQUE INDEX besdk_job_queue_unique ON besdk_job_queue (kind, unique_key)
    WHERE unique_key IS NOT NULL AND state <> 'done';   -- 同一个键同时只有一个未完成的作业；作业完成后键被释放
CREATE INDEX besdk_job_queue_due ON besdk_job_queue (kind, run_at) WHERE state IN ('ready', 'running');
```

**四种类型：**

| 类型 | 语义 | 机制 | 典型用户 |
|---|---|---|---|
| `every` | 每个副本都按自己的定时器跑；它取的工作是原子认领的，所以并发跑也安全 | 定时器；工作行用 `FOR UPDATE SKIP LOCKED` 认领 | outbox 推送泵、预留清扫、待办超期扫描 |
| `singleton` | 所有副本、所有进程里同一时间最多一处在跑 | 用 `UPDATE besdk_job_lease SET holder=$me, epoch=epoch+1, expires_at=now()+$ttl WHERE name=$n AND (expires_at < now() OR holder=$me) RETURNING epoch` 拿租约（行先用 `INSERT … ON CONFLICT DO NOTHING` 建好）；每过 TTL/3 续约一次；丢了租约就取消正在跑的这一次；不能重复发生的写入要校验 epoch | 分区维护、生命周期冻结、快照回填、游标与幂等键清理 |
| `cron` | 每个时间槽在所有副本里只跑一次 | `INSERT INTO besdk_job_slot … ON CONFLICT DO NOTHING`；插入成功的进程跑这个槽并写 `done_at`；不需要领导者；停机后只补跑最近一个错过的槽 | 日报、会计年度提醒 |
| `queue` | 在业务事务里入队，至少执行一次 | 入队就是和业务写入同一个事务里的一条 `INSERT`（随它一起回滚），设了 `unique_key` 时用 `ON CONFLICT DO NOTHING`；worker 用 `FOR UPDATE SKIP LOCKED` 认领 `state='ready' AND run_at <= now()` 的行，置为 `running` 并写 `lease_until`，然后**在任何事务之外**执行处理函数；失败时 `attempts` 加一，并按退避列表设 `run_at`；尝试用尽时置为 `dead`，并在一个事务里调用尽时的处理函数；`lease_until` 已过的 `running` 行可以被再次认领 | 异步命令、开异常待办、回查钉钉投递结果 |

- **cron 的时区。** cron 表达式按部署的业务时区求值，即共享键 `BUSINESS_TIMEZONE`（默认 `Asia/Shanghai`，见 [05-time-and-calendars.md](05-time-and-calendars.md)），除非任务自己声明了别的时区；没有单独的任务时区配置键。按法人工作的任务每个槽跑一次，在运行时为每个法人算出它自己的业务日期。
- **处理函数必须幂等。** 至少一次意味着处理函数可能跑两次；它按 `unique_key` 或业务键去重。
- **保留期。** `besdk_job_queue` 里状态为 `done` 的行 7 天后删除，`besdk_job_slot` 的行 30 天后删除，都由一个 `singleton` 清理任务执行（平台默认值，与 outbox 发布后 14 天、游标和幂等行 30 天并列，[09](09-data-lifecycle.md#分区窗口与平台表)）。这几张表不分区，靠保留期保持有界，与事件游标表、命令幂等表是同一个例外。

**监督。** 每个任务和 worker 各自独立运行。出错或 panic 时，用成员的 logger 按原因该有的级别记一条、计数，按指数退避从 1 秒到 5 分钟重启。一个任务停下绝不停掉别的任务。停机时取消正在跑的运行，给它们宽限期收尾。单跑和外壳用同一个监督者。

**指标**（每条序列还带 `component`）：`be_job_runs_total{job,result}`、`be_job_duration_seconds{job}`、`be_job_last_success_timestamp_seconds{job}`、`be_queue_depth{kind,state}`、`be_queue_oldest_age_seconds{kind}`。SDK 附带告警规则模板，例如"某个 singleton 连续三个周期没有成功"。

**运维端点**（可选，只读）：`GET /{domain}/{name}/_ops/jobs` 列出任务、上次成功时间、上次错误和队列深度；需要权限键 `<domain>.<name>.ops`，由 be-ops 登记。

**外壳里。** 这些表在每个成员自己的 schema 里，`holder` 写的是成员，所以成员之间从不共用租约、时间槽或队列（[27-shells.md](27-shells.md)）。

**"跑一次"入口**（可选的协议能力）。`<entrypoint> job run <name>`（be-protocol P14.8）用同一个镜像、同一份配置和密钥文件，像服务入口一样核对 schema 版本，不起服务、不起别的后台工作，经同样的表把声明过的任务 `<name>` **跑一次**，然后退出。`cron` 任务认领当前时刻及之前最近的一个时间槽；`singleton` 为这次运行抢租约；`every` 和 reconciler 照常认领、走一遍；`queue` 在任务超时之内把该种类就绪的行处理一遍。holder 是 `<组件 ID>/job-run:<实例 id>`。运行成功或无事可做（时间槽或租约已被拿走，日志里写明原因）退出 `0`，运行失败退出 `1`，任务名不存在退出 `4`，配置错误退出 `78`；所以两次触发、或一次触发加进程内的那一份，仍然只执行一次。`JOBS_OVERRIDES` 里的 `enabled: false` 只停掉进程内的调度。提供这个入口的运行时在 `/_be/info` 的 `capabilities` 里列出 `job_run`。把一个任务交给外部触发，分三步，按顺序：

1. 留在进程里（默认）；限制它的批量和并发。
2. 它在外壳里挤占了邻居，就把它的组件移出外壳、放进自己的容器并写 `resources.limits`（改部署文件即可，不改配置）。
3. 只有测量证明这样仍不够：在 `JOBS_OVERRIDES` 里设 `{"<name>": {"enabled": false}}`，从 brickKit 之外触发"跑一次"入口：
   - **Docker、Podman**：宿主机 cron 或 systemd 定时器执行 `docker compose --project-directory <项目根目录> -p brickkit-<项目名> -f <项目根目录>/.brickkit/generated/compose.yaml run --rm --no-deps <带版本的服务名> job run <name>`，用的是上一次 `up` 的镜像、环境变量和密钥挂载；服务名随每次升级而变，定时器里的那一行要跟着改。
   - **Kubernetes**：一个按组件生成的 Deployment 手写的 CronJob（取它的 Pod 模板、换掉命令），每次 `up` 之后重新生成，并且**不带** `brickkit.io/project` 标签，所以 brickKit 既不拥有也不删除它；命名空间是 brickKit 建的时候，`brickkit down` 会连同命名空间一起删掉它。

## 备选方案

| | Kubernetes CronJob | `pg_cron` | River（Go） | Graphile Worker / pg-boss（Node） | Temporal Schedules | APScheduler / Celery beat | DBOS | 基于 PostgreSQL 表的 SDK Jobs（选用） |
|---|---|---|---|---|---|---|---|---|
| 单机 Docker | brickKit 不生成 | 要装扩展、要超级用户，只能跑 SQL | ✓ | ✓ | 要集群 | Celery 要 broker | ✓ | ✓ |
| 外壳与单跑一致 | 否（另起一个镜像，配置要注入两遍） | 否 | ✓ | — | — | — | ✓ | ✓ |
| 在业务事务里入队 | — | — | ✓ | ✓ | — | — | ✓ | ✓ |
| 每种语言一致 | — | — | 只有 Go | 只有 Node | ✓ | 只有 Python | 部分语言 | ✓：表和行为就是协议 |
| 单例与按槽一次 | — | ✓ | 领导选举 + periodic job | ✓ | ✓ | 要额外加锁 | ✓ | ✓ |

## 为什么选它

- **两种形态行为一致。** 监督者和表在单跑和外壳里都一样，消除了今天的分裂（循环失败时，单跑会重启进程，外壳里却一直停着）。
- **每种语言行为一致。** 组件可以用任何语言写；绑定某一种语言的库做不了契约，表加语义可以。
- **在业务事务里入队。** 异步命令存在，当且仅当业务写入已经提交；没有"提交后尽力而为"的空档。
- **多副本下正确**，而且不需要领导者：singleton 用租约，cron 用时间槽行，queue 用 `SKIP LOCKED`。一期以单机为主，但多副本也必须正确。
- **不新增基础设施**，一个组件的全部任务在一处看全。

## 为什么不选其他

- **用 Kubernetes CronJob 当调度器**：brickKit 不生成它（也明确不做，FR06-007）；它带着第二份配置；Docker 上没有它，两个目标的行为会不一样。只把它当"跑一次"入口的触发器、而且在上面第 2 步之后，是允许的：只跑一次仍由表来保证。
- **`pg_cron`**：要扩展和超级用户，只能跑 SQL，项目目标里的 PostgreSQL 兼容发行版也不是都有（[03-database.md](03-database.md)）。
- **River、Graphile Worker、pg-boss、APScheduler、Celery**：各自绑定一种语言；用了它们，每种语言的语义就各不相同。
- **Temporal Schedules**：要一个 Temporal 集群，只有连工作流引擎一起引入时才值得（[11-consistency-across-components.md](11-consistency-across-components.md)）。

## 什么时候换

- 实测作业量超出 PostgreSQL 能承受的写放大（每秒上千个作业）：入队作业改走事件总线（[12-event-bus.md](12-event-bus.md)）。
- 测量证明某个任务即使在它组件自己的容器里也太重：用"跑一次"入口加外部触发（[端口契约](#端口契约)里的第 3 步）。
- 出现第一个跨天、多人、长时间的流程：按 [11-consistency-across-components.md](11-consistency-across-components.md) 评估工作流引擎（先 DBOS，再 Temporal）。那时 DBOS 可以成为 `queue` 的第二个实现。

## 怎么换

这是一个**单适配器端口**，如实标注（[01-ports-and-adapters.md](01-ports-and-adapters.md)）：它的价值是一套语义加一个一致性套件，不在于能换。`queue` 的第二个适配器会放在各 SDK 内部、同一份声明后面；组件的声明不变，而且表归 SDK 所有，组件不用做迁移。

## 一致性测试

套件 `tools/be-acceptance/conformance/jobs/`（已定），对每个官方 SDK 写成的夹具组件跑：

- 两个副本：一个 `cron` 时间槽只跑一次（CP-JOBS-01：平台的 cron 任务 `be.cleanup` 通过 `JOBS_OVERRIDES` 设成 `@every 2s`）；
- 两个副本：`singleton` 同一时间只在一处跑；丢了租约的那次运行被取消；
- 任务 panic 后按退避重启并计数；一个任务停下，其余任务照常运行；
- `queue`：业务事务回滚则作业不存在；尝试用尽时调用尽时的处理函数；正常运行下两个副本每个作业只执行一次；
- 外壳：成员失败的任务被重启，而不是一直停着（今天是红的）；
- 跑一次，CP-JOBS-06（对列出 `job_run` 的运行时）：同时启动两次 `job run <name>`，一个时间槽只执行一次，两个都退出 `0`；用 `JOBS_OVERRIDES` 关掉进程内的那一份之后，入口被触发之前什么都不跑。

迁移前先写红的组件测试：finance"一个循环退出时其余循环被取消"；inventory"两个副本并发维护分区不报错""分区 DDL 被长事务阻塞时在 `lock_timeout` 内放弃且不堵写入"。门禁 `module-ticker-scan`（已定）对模块代码里的定时器循环告警。

## 相关决策

- [0508 后台工作只经 SDK 的 Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md)：本文是它的完整分析。
- [0501 事务里不发网络调用](../02-decisions/05-runtime/0501-no-network-inside-a-transaction.md)：在业务事务里入队，是异步的出口。
- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：任务表在组件自己的 schema 里。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：启动器、也就是监督者，在 SDK 里。

## 已知限制

- 只有一个适配器；这个端口为统一语义而存在，不为替换。
- cron 精度约一秒；停机后只补跑最近一个错过的槽，必须覆盖每个错过日子的任务要自己遍历缺口。
- 崩溃的 singleton 要等租约到期（最多一个 TTL）才由别处接手。
- 至少一次：处理函数必须幂等。
- 吞吐受组件 schema 里 PostgreSQL 写入能力的约束。
- 外部触发器在 brickKit 之外：它的时间表不在 `component.yaml` 里，Docker 上的命令里写着带版本的服务名、每次升级都要改，手写的 Kubernetes CronJob 不在每次 `up` 后重新生成就会漂移。外壳成员没有自己的服务可以 `run`；先把它移出外壳。
