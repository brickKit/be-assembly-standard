[English](../../en/04-foundations/11-consistency-across-components.md) · [中文](11-consistency-across-components.md)

# 跨组件一致性

一个业务动作碰到两个或更多组件时，状态怎么保持正确：outbox、按聚合流为键的消费者游标、幂等命令、放在业务行上的 saga、推动卡住流程的 reconciler、带期限的预留，以及用户在写入之后马上能读到什么。读者是设计跨组件边界流程的人、写消费者或补偿步骤的人，以及提议引入工作流引擎的人。

## 范围

- **在本文：** 一个组件里的变更引起另一个组件的变更、或必须与之一致的全部机制；这类流程的失败、重试与恢复；跨组件的读己之写预期。
- **不在本文：** 一个组件内的一个事务（[10-local-transactions.md](10-local-transactions.md)）；broker、流、持久消费者（durable）和死信（[12-event-bus.md](12-event-bus.md)）；事件信封和契约文件（[13-event-contracts.md](13-event-contracts.md)）；线上的同步调用（[14-system-rpc.md](14-system-rpc.md)）；承载异步命令的作业表（[19-background-jobs.md](19-background-jobs.md)）。

## 选择

一致性分五层构建。每一层只用它下面的层。

| 层 | 内容 | 由谁提供 |
|---|---|---|
| 本地 | 一个组件内的 ACID | [10-local-transactions.md](10-local-transactions.md) |
| 事件 | outbox → 总线 → 消费者；至少一次投递，靠每个聚合流一个游标做到实际上恰好一次 | 事件总线端口（[12](12-event-bus.md)、[13](13-event-contracts.md)） |
| 命令 | 同步：带幂等键的 gRPC 加 `GetStatus`；异步：在业务事务里入队一个作业，提交后执行、重试，一直失败就升级处理 | [14-system-rpc.md](14-system-rpc.md)、[19-background-jobs.md](19-background-jobs.md) |
| 流程（saga） | 业务行上的状态机，带一个截止时间列，由 reconciler 向前或向后推动；每个补偿都是一个命令 | 组件自己的代码，以及下文的 reconciler 契约 |
| 人 | infra/workflow 里的异常待办；死信工具 | infra/workflow，`make dlq-ls` / `make dlq-replay`（计划中） |

由此得出的规则：

1. **用户在等的那一步是同步的**（经 gRPC 的 try-confirm-cancel）：点"确认"的用户必须当场知道"缺货"。**之后的每个副作用都是异步的**，经由一个事件或一个入队的命令。不存在"提交后调用一下，但愿能成"这回事。
2. **流程住在发起它的组件里。** 没有中央编排组件。流程的状态就是业务行；其他组件只能通过 `GetStatus` 和事件看到它。
3. **消费者的游标按聚合流为键**，不按 subject，所以同一个聚合在不同 subject 上的事件永远不会被乱序应用。
4. **幂等键按调用方划分命名空间**，并绑定到命令、它的目标和请求的指纹。
5. **每个进行中的状态都有截止时间**，reconciler 处理超过截止时间的行。完成不了的流程以 `SUSPENDED` 结束，并给人开一个异常待办。

**状态**：已定；随组件协议和 3.0.0 统一升级落地。今天事件走不带持久化的 core NATS，消费者收件表按 subject 去重，而且在分区表上扛不住并发投递，有三处远程调用是"提交后尽力而为"，恢复逻辑有六种不同写法。

## 端口契约

每个实现、不论哪种语言，都要建的表和遵守的规则。这些表在每个组件自己的 schema 里，带 `besdk_` 前缀，由 SDK 的平台迁移创建；组件的 SQL 从不碰它们。规范性的 DDL 放在计划新建的 `brickKit/be-protocol` 仓库的 `sql/platform/` 里。

### 生产者的 outbox

```sql
CREATE TABLE besdk_outbox (
    id                UUID        NOT NULL,             -- UUIDv7；成为 ce-id 和 broker 的消息 ID
    created_at        TIMESTAMPTZ NOT NULL,             -- 由 id 推导
    subject           TEXT        NOT NULL,             -- ce-type
    aggregate_type    TEXT        NOT NULL,             -- 在事件契约里声明
    aggregate_id      TEXT        NOT NULL,             -- ce-subject
    aggregate_version BIGINT      NOT NULL,
    occurred_at       TIMESTAMPTZ NOT NULL,
    traceparent       TEXT        NOT NULL DEFAULT '',
    causation_id      TEXT        NOT NULL DEFAULT '',
    hop_count         INT         NOT NULL DEFAULT 0,
    headers           JSONB       NOT NULL DEFAULT '{}', -- 其他 ce-* 扩展属性，例如 legalentity
    payload           JSONB       NOT NULL,
    status            TEXT        NOT NULL DEFAULT 'PENDING',  -- PENDING | SENDING | PUBLISHED
    attempts          INT         NOT NULL DEFAULT 0,
    next_attempt_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_until     TIMESTAMPTZ,
    published_at      TIMESTAMPTZ,
    last_error        TEXT        NOT NULL DEFAULT '',
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
```

- 这一行和业务变更在同一个事务里插入。推送泵原子地认领行、发布，只有在 broker 确认已存下消息之后才标记为 `PUBLISHED`（[12-event-bus.md](12-event-bus.md#端口契约)）。
- **outbox 是回放的事实来源**；broker 只是传输。行在发布后在线保留 14 天；更早的历史从生产者的 `List` 或它发布的数据集读（[12](12-event-bus.md)）。
- 同一个 `aggregate_type` 的所有 subject 共用一个严格递增的 `aggregate_version`（[13-event-contracts.md](13-event-contracts.md)）。

### 消费者游标

```sql
CREATE TABLE besdk_event_cursor (
    consumer       TEXT        NOT NULL DEFAULT '',   -- 一个投影的名字；'' 是组件的默认投影
    aggregate_type TEXT        NOT NULL,
    aggregate_id   TEXT        NOT NULL,
    version        BIGINT      NOT NULL,
    event_id       TEXT        NOT NULL,
    seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (consumer, aggregate_type, aggregate_id)
);

-- 一条语句判定"新的还是过时的"并推进游标；没有返回行 = 跳过。
INSERT INTO besdk_event_cursor (consumer, aggregate_type, aggregate_id, version, event_id)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (consumer, aggregate_type, aggregate_id) DO UPDATE
   SET version = EXCLUDED.version, event_id = EXCLUDED.event_id, seen_at = now()
 WHERE besdk_event_cursor.version < EXCLUDED.version
RETURNING 1;
```

- **故意不分区**：主键里一旦带上分区键，两次并发投递就可能都插入成功，这正是今天分区收件表的毛病。这张表靠保留期保持有界：30 天没见到的行会被删除。
- **本地处理函数**把上面那条语句和业务写入放在**一个事务**里执行。并发的重复投递在这一行上串行化：第二个先等待，然后发现 `version` 已经不再更小，于是跳过。
- **有外部副作用的处理函数**（发一条 IM 消息、调用另一个组件）在任何事务之外运行；成功之后，游标在一个短事务里推进。并发的重复投递可能跑两次，所以这类处理函数要按业务键做到幂等（例如用从事件推导出的幂等键）。
- **状态模式（默认）：** 处理函数写成"把我的投影推进到该聚合在版本 v 时的状态"。更旧的版本被跳过。例子：finance 先收到 `cancelled`（v3），后收到 `created`（v2）。此时还什么都没入账，它记下"已取消，未入账"；随后到来的 `created`（v2）被跳过。结果是对的；换成按 subject 的游标，就会给一张已取消的订单记一笔应收。
- **序列模式**（每一次变更，按顺序）保留不建（[13-event-contracts.md](13-event-contracts.md)）。
- 一个组件里有两个独立的投影都需要每个版本时，用两个 `consumer` 名字。

### 被调方的命令幂等

```sql
CREATE TABLE besdk_idempotency (
    caller          TEXT        NOT NULL,   -- user:<平台 sub> | svc:<组件 ID> | system
    idempotency_key TEXT        NOT NULL,
    command         TEXT        NOT NULL,   -- 命令的权限键，例如 erp.sales.confirm
    target          TEXT        NOT NULL DEFAULT '',  -- 它作用的聚合；"创建"时为空
    request_hash    BYTEA       NOT NULL,   -- 按 RFC 8785（JCS）规范化后请求的 SHA-256
    status          TEXT        NOT NULL DEFAULT 'CLAIMED',  -- CLAIMED | DONE
    result          JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,   -- created_at + 30 天
    PRIMARY KEY (caller, idempotency_key)
);
```

- **键按调用方划分命名空间。** 别的调用方的键，对我来说是一个没用过的键：我读不到它的结果，接管不了系统推导出来的键（比如从商机 ID 推导出的键），也无从得知它存不存在。
- **同一调用方、同一个键：** `command`、`target` 或 `request_hash` 不同，以 `INVALID_ARGUMENT` / `IDEMPOTENCY_MISMATCH` 失败；认领了但还没完成，答 `ABORTED` / `IDEMPOTENCY_IN_PROGRESS`；已完成的，返回存下的结果，不再执行。
- **两步命令**（认领、一次网络调用、再完成）在调用期间保持 `CLAIMED`；某一步确定失败时删除认领，这样同一个键可以重试。
- **命令里的检查顺序**：校验参数，对目标和数据范围鉴权，然后查找或认领键，然后检查状态机，最后写入（[02-backend.md](../01-conventions/02-backend.md#事件与跨组件写入)）。"创建"命令的重放，通过组件自己带范围限定的读取读回；超出范围的，按不匹配回答。
- **键的有效期是 30 天**；过期之后，同一个键就是一个新命令。每个带键命令的契约都要写明这一点。
- 事件处理函数为下游命令使用的键从事件推导（`crm-won:<商机 ID>`），所以一次重投就是用同一个键的一次重试。
- 每个跨组件写入的被调方都提供按键的 `GetStatus`；超时之后，调用方先问一下，再决定是否补偿（[02-backend.md](../01-conventions/02-backend.md#事件与跨组件写入)）。

### 异步命令

业务变更之后必须发生的远程副作用，**在同一个事务里**入队为一个 `queue` 作业（[19-background-jobs.md](19-background-jobs.md#端口契约)）；必须只发生一次时带上 `unique_key`。它在提交后、在任何事务之外，按作业的退避运行；尝试用尽时，由作业在用尽时的处理函数标记业务行并开一个异常待办，开待办这件事本身也经由一个入队的命令。例子：开"信用被拒"待办、确认失败后释放预留、回查 IM 投递结果。

### 流程状态与 reconciler

- 业务行持有流程状态，包括进行中的状态（`CONFIRMING`）和一个 `deadline_at`。合法的状态转换在组件里的一张表中声明（[09-ai-development.md](../01-conventions/09-ai-development.md#何时用设计模式)）。
- **reconciler** 是一个声明好的任务：每个周期用组件自己的 SQL 选出候选（非终态且 `deadline_at < now()`），逐个认领，在任何事务之外调用它的处理函数，再在一个重新检查状态机的短事务里应用结果。它的记账放在一张旁表里，业务表不用加任何通用列：

```sql
CREATE TABLE besdk_reconcile (
    name        TEXT        NOT NULL,   -- reconciler 的名字
    item_id     TEXT        NOT NULL,
    attempts    INT         NOT NULL DEFAULT 0,
    next_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    lease_until TIMESTAMPTZ,
    last_error  TEXT        NOT NULL DEFAULT '',
    PRIMARY KEY (name, item_id)
);
-- 认领：INSERT … ON CONFLICT (name, item_id) DO UPDATE SET lease_until = now() + $lease
--        WHERE (besdk_reconcile.lease_until IS NULL OR besdk_reconcile.lease_until < now())
--          AND besdk_reconcile.next_at <= now()
--        RETURNING attempts;
```

- 到达终态就删除旁表的行；否则 `attempts` 增加，`next_at` 按退避推后。超过最大次数，reconciler 放弃：业务行变为 `SUSPENDED`，并入队一个异常待办。
- 指标：`be_reconcile_pending{name}`、`be_reconcile_oldest_age_seconds{name}`、`be_reconcile_giveups_total{name}`。合起来回答"有多少流程卡住了，从什么时候开始"。
- 现有和计划中的用户：sales 的 `CONFIRMING`、挂起与解除标志；inventory 对过期预留的清扫；finance 等待客户快照的信用检查；IM 适配器的投递结果回查；infra/workflow 的超期扫描；iam 的 webhook 投递。

### 带期限的预留

try 步骤预留的资源带一个由调用方选定的期限，这样消失了的调用方也不会永远占着它；confirm 步骤清除期限。inventory 的预留就是这样：预留时传 `hold_seconds`（sales 要 900 秒，inventory 上限 3,600 秒），`HoldReservation` 作为 confirm，一个清扫任务释放过期的预留并发布过期事件。没有期限的预留（来自老的调用方）列出来给人审查，绝不自动释放。

### 读己之写

1. **同一个组件内：** 命令的响应带上新状态和 `version`；页面用响应更新，不重新读取。
2. **另一个组件里的派生视图**（确认订单后的应收台账、商机上的订单号、通知）是最终一致的。派生视图的 `List` 和 `Get` 可以返回 `X-Data-As-Of`：这个投影已处理的最新事件的 `occurred_at`（[15-user-api-and-errors.md](15-user-api-and-errors.md)）。用户刚写过而视图更旧时，前端显示"同步中"并重新读取，最多持续 10 秒。每个消费者导出 `be_consumer_lag_seconds{subject}`。
3. **必须是最新的值**（确认后马上要看的可用库存）同步地向它的所有者要，绝不从投影里读。
4. 授权提供方的一致性令牌，是同一机制在权限上的应用（[20-authorization-provider.md](20-authorization-provider.md)）。

## 备选方案

| | 模型 | 额外服务 | 与本项目的契合度（单机优先、每组件一个 schema、外壳、每个组件自选语言） | 我们从中借鉴什么 |
|---|---|---|---|---|
| Seata | AT（undo log 加全局锁）、TCC、saga 状态机、XA | 一个 Java 协调器 | AT 代理数据源并改写 SQL，与不用 ORM 的静态 SQL 相冲突；全局锁把单库的竞争带到了组件之间 | TCC 的三种异常：空回滚、幂等、悬挂（由 `GetStatus`、幂等键和预留期限覆盖） |
| Temporal / Cadence | 工作流即确定性代码，从历史回放 | 一个服务端集群加它的数据库 | 能在单机上跑，但又是一个要运维、要备份的有状态服务；确定性对 AI 写的代码是个看不见的陷阱 | 持久定时器、按步骤的重试策略、每个实例的历史 |
| DBOS | 以库的形式提供持久工作流，检查点存在 PostgreSQL | 无 | 最契合；它的表能否放在组件的 schema 里、能否与我们的事务共用，有待验证 | 如果哪天需要引擎，首选候选 |
| Restate | 基于日志的持久执行 | 一个单二进制服务端 | 又一个常驻服务 | — |
| Dapr | 带 pub/sub、状态和工作流的 sidecar | 每个应用一个 sidecar | 外壳把成员合并成一个进程、只有一个 app ID；sidecar 违背"没有网关、没有网格" | pub/sub 抽象就是我们的总线端口；CloudEvents 信封 |
| Axon | 事件溯源、saga、截止时间管理器 | Axon Server（可选） | 只支持 Java | 截止时间是 saga 的一等组成部分 |
| Eventuate Tram | 事务性 outbox、消费者去重表、基于消息编排的 saga | 一个 CDC 服务（可选） | 与我们的机制最接近 | `received_messages` ≈ 我们的游标；saga 实例 ≈ 我们的业务行；命令通道 ≈ 我们的入队命令 |
| 两阶段提交（XA） | 一个全局事务 | 一个事务管理器 | 协调器故障时阻塞；锁跨组件持有 | — |

## 为什么选它

- **不新增常驻服务**，其中也没有任何东西依赖组件用什么语言写：只有表、语句和规则。
- **合并安全。** 每张表都在成员自己的 schema 里；组件单跑和在外壳里行为相同。
- **状态可读。** 崩溃之后，世界的样子是"一张订单从 10:02 起卡在 `CONFIRMING`"，用户、运维和 AI 都看得见，由一个 reconciler 推着往前走。
- **每一层的失败都有主人**：总线重投，队列重试，reconciler 推动，人接到待办。没有任何东西是"尽力而为"。

## 为什么不选其他

- **Seata AT** 改写 SQL 并持有全局锁；它与静态 SQL、每组件一个 schema 相矛盾。
- **Temporal** 为了我们还没有的流程，引入一个集群和一套确定性纪律。
- **Dapr** 的 sidecar 与外壳、与不用网格的方向相冲突。
- **自己做一个通用 saga 引擎或 DSL**，没有第二种编排形态来证明它值得；可复用的部分（持久定时器、租约、重试、幂等命令、升级处理）已经在作业和 reconciler 的契约里了。
- **两阶段提交**在协调器故障时阻塞所有参与方，并且在最慢的那个参与方的整个时长里跨组件持有锁。

## 什么时候换

出现这样一个流程时评估工作流引擎：跨至少三个组件、至少五个步骤，包含以天计的人工等待，并且需要每个实例的历史，或需要把运行中的实例迁移到新版本（采购到付款、项目里程碑开票）。先评估 DBOS（一个库，原生 PostgreSQL，单机），再评估 Temporal（接受要运维一个集群）。

## 怎么换

引擎只替换**驱动**：推动流程的 reconciler 和入队命令。业务状态表、`GetStatus`、事件以及其他每个组件的契约都保持原样，因为流程住在发起它的组件里，并且只通过这些东西被看到。一次换一个组件，从触发这次替换的那个流程所在的组件开始。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/bus/`（游标用例）和 `tools/be-acceptance/conformance/jobs/`（队列和 reconciler 用例）；组件用例在统一升级前先写成红的。

- 同一聚合的两个 subject 共用一个游标：先 `cancelled`（v3）后 `created`（v2），结果是"已取消，未入账"。
- 旧版本和重复投递在游标语句上不返回行；并发的重复投递只执行一次业务写入。
- reconciler：两个副本对同一项只处理一次；失败的处理函数按退避推后，到最大次数时放弃；在处理函数和应用结果之间崩溃，下一轮会接着做。
- 入队命令：随业务事务一起回滚；用同一个 `unique_key` 入队两次，只执行一次。
- 幂等：重放返回第一次的结果；command、target 或请求体变了，以 `IDEMPOTENCY_MISMATCH` 失败；两个调用方用同一个键互不影响；system 和 user 的命名空间相互独立；并发的首次使用只执行一次；进行中的认领答 `IDEMPOTENCY_IN_PROGRESS`；释放了的认领可以重试；过期的键是新的。
- **属性测试模板，每个消费者一份**（[06-testing.md](../01-conventions/06-testing.md#l2-业务规则测试)）：一组事件任意打乱并带重复投递，最终状态与按顺序各投递一次相同。
- erp/finance：`cancelled` 先于 `created` 到达时，不记应收。
- erp/sales：infra/workflow 不可用时，它恢复之后"信用被拒"的异常待办存在（今天是红的：丢了）；被重启打断的补偿会继续（今天是红的：它活在一个休眠的请求里）。
- erp/sales 和 crm/opportunity：用户发来一个系统会推导的键，不影响系统的命令；另一个调用方的种子键拿不到任何属于他们的东西。

## 相关决策

- [0101 组件之间绝不互相 import](../02-decisions/01-architecture/0101-no-imports-between-components.md) 和 [0102 每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：一致性经由线上达成，状态放在每个组件自己的 schema 里。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：新的流程状态（如 `CONFIRMING`）是对枚举的追加。
- 计划新增、尚未编号："流程住在发起它的组件里，它的状态就是业务行"；"提交后的远程副作用经由入队命令"；"事件至少投递一次，靠每个聚合流一个游标去重"；"幂等键按调用方划分命名空间"；"不分区的有界表"（游标表、幂等表、reconcile 表和作业表，靠保留期保持有界）。

## 已知限制

- **序列模式没有建**；需要按顺序拿到每一次变更的消费者只能等它。
- **跨组件视图只是最终一致的**；前端必须显示"同步中"。
- **有副作用的处理函数和 reconciler 处理函数至少运行一次**；它们按业务键的幂等由组件负责。
- **30 天后重用的键是一个新命令。** 确认和取消会被状态机挡住；"创建"会再创建一次。
- **没有期限的预留**，来自不传期限的调用方，不会被自动释放。
