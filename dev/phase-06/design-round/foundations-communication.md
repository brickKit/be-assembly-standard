# 基础层：本地事务、跨组件一致性、同步通信、消息队列、缓存、边缘、后台任务与外壳——审查与设计提案

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准（be-sdk-go / be-sdk-python / be-sdk-ts 都在 v0.5.0；组件都在各自的 2.x tag 上）。
> brickKit 只读了本机安装版本（`brickkit docs` 显示 v1.1.0）的文档页：`09-patterns/04-service-calling`、`09-patterns/01-component-design`、`04-shell/05-shell-development`、`04-shell/01-shell-concept`、`06-architecture/05-design-principles`、`06-architecture/03-env-injection-contract`、`01-three-layers/03-deploy-yaml`、`11-reference/01-component-yaml-schema`、`11-reference/03-deploy-yaml-schema`。**没有读 brickKit 源码。**
> 已有四份分析（`events-consistency.md`、`data-layer.md`、`identity-permissions.md`、`authz-architecture.md`）的结论在本文里当作前提，不重复。本文只写它们没有覆盖的部分，以及和它们**不一致**的地方（§0.4 列出）。

**判据（用户 2026-10-02）**：业务逻辑错了可以重写；基础逻辑（事务规则、组件间通信、协议、队列）要一次设计对。宁要完整、面向未来、不弱于主流平台的设计。几种设计各适合不同场景时，做成可替换的适配器或组件：先定契约，再配一致性测试（六边形：端口与适配器）。换实现可以需要简单修改，不能需要重写逻辑。

---

## 0. 结论

### 0.1 最要紧的缺口（按危害排序）

1. **全项目没有任何超时设置。** 在 SDK、组件、shell 和 infra 里 grep `statement_timeout`、`lock_timeout`、`idle_in_transaction`、`SetMaxOpenConns`、`ReadHeaderTimeout`、`keepalive`、`MaxRecvMsgSize`，结果全部为空。具体表现：
   - `http.Server` 零超时（`tools/be-sdk-go/standalone.go:187`）；
   - iam 登录路径调 authz 的 `ResolveClaims` 时不带截止时间（`components/infra/iam-casdoor/backend/internal/service/service.go:226-233`）；
   - BFF 的 `fetch` 不带超时（`components/infra/bff-mobile/src/clients/restForward.ts:69,84`）。

   brickKit 自己的实验（`09-patterns/04-service-calling`）结论是："Node 不设超时，那一个请求会无限挂起。"所以只要一个下游变成黑洞，登录和移动端整条链路就会挂死。
2. **连接池没有上限，也没有舱壁。**
   - Go 侧 `sql.Open` 之后从不调用 `SetMaxOpenConns`（`standalone.go:79`、`shell/run.go:113`）。外壳里十几个成员共用一个无上限的池，一个成员的突发流量就能吃光 PG 的 `max_connections=300`（`infra/docker-compose.infra.yml:33`），全部成员一起报错。
   - Python 外壳正好反过来：`asyncpg.create_pool` 默认上限 10（`tools/be-sdk-python/besdk/shell_runner.py:126`、`standalone.py:103`），全部成员挤 10 条连接。
   - 再叠加一种写法：消费事务开着，handler 自己再开一个 WithTx（sales 赢单，`erp/sales/backend/internal/consumer/consumer.go:183-209`）。这样一旦设了上限，就会出现**池饥饿死锁**。
3. **gRPC 每次调用都现拨一条连接**（`be-sdk-go/client.go:84-87`，以及 `:102-106` 的注释"每次用户请求都现拨一条连接"；sales 的 `internal/client/client.go:13`）。
   - 后果：每个请求多一次 TCP + HTTP/2 握手；没有 keepalive、service config、重试、OTel，也没有默认截止时间。
   - 改成复用连接是必须的。但一旦复用，K8s 上 `replicas>1` 时 gRPC 长连接会钉在一个 Pod 上（kube-proxy 只做 L4）。今天"每次现拨"恰好把这个问题掩盖了。
4. **NATS 断线约两分钟后就永久失联。** `nats.Connect(url)` 不带任何选项（`standalone.go:89`、`shell/run.go:123`，Python 的 `standalone.py:110` 同理）。nats.go 默认最多重连 60 次、每次间隔 2 秒，所以 NATS 停机超过约 2 分钟，订阅就永久死亡，而 `/healthz` 照样是绿的。另外，核心订阅的回调没有设置异步错误处理器，慢消费者被丢消息时**连日志都没有**。
5. **持锁做网络调用**：除了 events-consistency §2.1.5 列出的两处，还有第三处。sales 的 `finance.credit.rejected.v1` handler 先用 `SELECT … FOR UPDATE` 锁住订单（`repo/suspend.go:41`），然后在同一个消费事务里同步调 workflow 的 `CreateTask`，最长 5 秒（`consumer/consumer.go:85-99` → `tcc/credit_rejected.go:56-79`）。这段时间里，对这张单的取消、发货全部排队。待办是"尽力而为"：workflow 挂了就永远没有这条待办。
6. **多品预留按请求顺序加锁**（`erp/inventory/backend/internal/repo/reservation.go:66-79`）。两张单按相反顺序预留同样两个 SKU，就是教科书式死锁。PG 会杀掉其中一方，40P01 一路传回 sales，被当成"预留失败"直接报给用户（`tcc/confirm.go:107-111`）。全项目**没有任何一处**对 40001 / 40P01 做重试。
7. **跨 subject 乱序会记错账**（这一条修正 events-consistency §1.2）。
   - 那份提议里，`event_cursor` 的主键是 `(subject, aggregate_id)`。finance 以后要同时消费 `sales.order.created.v1` 和 `.cancelled.v1`（events-consistency §8 已定为 bug 修）。
   - 这两条是不同的 subject，各有各的游标。如果 `cancelled` 先到、`created` 后到，两条都会被接受，结果是**给一张已经取消的订单记了应收**。
   - 结论：游标必须按**聚合流**（`aggregate_type, aggregate_id`）建键。
8. **trace 在每一跳都断。** 三个 SDK 都没有设传播器，也没有 otelgrpc / otelhttp（grep 为空）。`X-Request-Id` 只在入站时生成（`be-sdk-go/gin.go:80-92`），出站不带。SDK 自己记日志用的是 `slog.Default()`（`events.go:69`），进外壳以后丢了成员 ID。
9. **后台循环没人看管。**
   - 12 份手抄的 `partition` 包，各自一个 ticker。多副本同时"先查后建"分区（`erp/inventory/backend/internal/partition/partition.go:85-110`），而且没有 `lock_timeout`。
   - 外壳里，成员的 `Start` 失败只记一行日志，之后就一直停着（`shell/run.go:164-181`）；单跑时同样的失败会让进程退出、由平台重启。**两种形态行为不一致。**
   - 组件的 `Start` 在任一循环退出时直接返回，其余循环没人取消（如 `erp/finance/backend/module/module.go:54-66`）。
10. **边缘层是空的。**
    - `assembly.yaml` 声明了 `edge_routes`（如 `erp/sales/assembly.yaml:6-7`），但 `tools/be-ops` 里 grep `edge` 为空，没有任何代码读它；`infra/traefik/dynamic/` 是空目录。
    - 0201 说"限流归网关"，可网关上没有任何中间件。
    - `infra/resources.tsv:11-12` 把 kafka、rabbitmq 登记成 `mq` 的互斥替换件，可 SDK 只会讲 NATS。这个承诺兑现不了。

### 0.2 主要建议

- **基础端口登记表**（§2）：Store/Tx、EventBus、Jobs、RPC、UserAPI、Cache、Edge、Telemetry、ObjectStorage、AuthzProvider、IdentityProvider。
  - 每个端口有四样东西：一个 SDK API（组件唯一能看到的东西）、一个默认适配器、具名的备选、一套 `be-acceptance/conformance/<port>/` 一致性测试。
  - 换适配器的方式是改共享地址的 URL scheme 或项目配置，组件代码零改动。
- **本地事务**（§3）：
  - 接口为 `Store.Tx(ctx, opts, fn(ctx, tx))`。默认 READ COMMITTED，每个事务 `SET LOCAL statement_timeout=5s, lock_timeout=2s, idle_in_transaction_session_timeout=30s`。
  - 40001 / 40P01 自动重试：fn 只碰事务，天然可以重放。
  - 隔离手段按阶梯选："约束 > 条件 UPDATE > 排序行锁 > 事务级 advisory 锁 > SERIALIZABLE"。
  - **事务内发起网络调用，由 SDK 在运行期拒绝。**
- **跨组件一致性**（§4）：
  - 保留 events-consistency 的 outbox + JetStream + 命令幂等 + "业务行即 saga 日志"。
  - 游标键改为聚合流。
  - "提交后尽力而为"的远程调用一律改成**事务内入队的异步命令**（`Jobs.Queue`）。
  - 新增 SDK 帮手 `Reconciler`：按状态与期限扫描、加租约、退避，超过上限后挂起并开待办。
  - **不建可替换的通用工作流引擎端口**，但写清楚 DBOS / Temporal 的切换条件。
- **同步通信**（§5）：
  - 维持"gRPC = 组件间系统面，REST = 用户面"（identity-permissions §5）。
  - SDK 负责的部分：
    - 按（成员、依赖、端口）复用连接；
    - 服务端 `MaxConnectionAge` 轮换连接，可选 headless + 客户端负载均衡；
    - 截止时间预算：入站默认 10 s，出站继承剩余预算；
    - 按 proto 标准的 `idempotency_level` 生成重试策略，配重试预算；
    - 统一错误模型：gRPC 用 `google.rpc.Status` + `ErrorInfo`，REST 用 RFC 9457 problem+json，两边共用一份 reason 登记表；
    - W3C traceparent 贯穿全链路。
  - 不引入 Connect-RPC，也不引入熔断库，改用舱壁 + 重试预算。
- **消息队列**（§6）：
  - 维持 JetStream。Broker 做成 SDK 内部端口，配一致性套件。
  - 第二个适配器选 **PG 队列**：用于最小安装和测试替身，同时证明端口真的可换。Kafka 适配器等客户提出时再建。
  - 信封改用 CloudEvents 属性名。
  - **生产者的 outbox 表是回放的事实源**，流只负责传输。
- **Redis**（§7）：0201 维持，措辞改成"没有缓存服务器；缓存只在进程内，经 `besdk.Cache`"。逐项核对的 11 类需求里，没有一项需要共享缓存。
- **边缘**（§8）：
  - be-ops 从 `edge_routes` 生成路由表：Docker 生成 Traefik file provider，K8s 生成 Ingress 或 Gateway API。
  - 网关只做 TLS、路由、粗粒度限流、请求体上限、超时，以及生成 traceparent。
  - 鉴权和授权永远在服务里做。
- **后台任务**（§9）：
  - 用 `Module.Jobs` 声明式登记，一个文件就能看全。SDK 负责监督：panic 恢复、退避重启、指标。
  - 四种语义：竞争式 `Every`、租约式 `Singleton`、按时间槽只跑一次的 `Cron`、事务内入队的 `Queue`。
  - 不用 K8s CronJob，也不用 pg_cron。
- **外壳**（§10）：用一张表逐项核对。新增三条外壳不变量：
  - 每个成员一份连接预算（舱壁）；
  - 每个成员一个 TracerProvider，`service.name` 是成员 ID；
  - advisory 锁、租约和 gRPC 的 `be-caller` 都带成员 ID。

### 0.3 文档目录（详见 §11）

放在 `docs/{en,zh}/04-foundations/`。原计划的 `04-operations/` 顺延为 `05-operations/`，它还没有写。

- 共 18 份，每份对应一个关键选择，统一使用 11 个 `##` 小节。
- `02-decisions/` 只留结论，结论里链到 foundations 的对应小节，理由不重复写。

### 0.4 与前四份不一致或需要补充的地方

| 前文 | 前文结论 | 本文 | 理由 |
|---|---|---|---|
| events-consistency §1.2 | `event_cursor` 主键为 `(subject, aggregate_id)` | 主键改为 `(aggregate_type, aggregate_id)`；事件契约显式声明 `x-aggregate-type` | 同一聚合的多个 subject 必须共用一个版本游标，否则乱序时会记错账（§4.2 C1） |
| events-consistency §1.1 | 信封头用 `X-` 前缀 | 改用 CloudEvents 属性名（`ce-id`、`ce-source`、`ce-type`、`ce-time`、`ce-subject` 加扩展属性），并兼容读取旧的 `X-` 头 | Broker 端口要能换成 Kafka 或 PG 队列，头名必须中立（§6.3） |
| events-consistency §4.4、§2.2.3 | 不加作业抽象；周期循环要不要进 SDK 交给 sdk-redesign 决定 | 加 `Jobs` 端口和 `Reconciler` 帮手 | 现成用户已有 10 处以上（§9.1），而新判据要求基础层一次设计对 |
| data-layer §7 D6 | 把 `ClaimBatch` 收进 SDK | 并入 `Jobs.Queue` / `Reconciler` | 两个名字说的是同一件事 |
| data-layer §3.4 | 生命周期任务每个 schema 一把 advisory 锁 | 改用 `Jobs.Singleton` 的租约 | 统一单例语义，并且可观测 |
| identity-permissions §5.3 | `Dial` 每次返回一条新连接 | 连接由 rt 按（依赖、端口）复用；`be-actor-sub` 在每次调用时从 ctx 读取 | 复用以后，拨号时刻的 ctx 不等于调用时刻的 ctx（今天的 `forwardAuthInterceptor` 就是在拨号时取值，`client.go:102-115`） |
| 0103 | BFF 用 Apollo Server 4 | 实际是 graphql-yoga 5.22（`be-sdk-ts/package.json:23`） | 文档漂移，修订 0103 |

---

## 1. 范围与前四份的分工

| 议题 | 已经在哪里定了 | 本文补充 |
|---|---|---|
| 本地事务 | data-layer §2：`Store` 绑定身份 | 隔离级别、超时、重试、加锁顺序、advisory 锁、长事务、"事务内不许走网络"的运行期守卫、池与舱壁 |
| 事件送达 | events-consistency §2：JetStream、DLQ、Apply/Run | 队列选型对照、Broker 端口、CloudEvents 信封、聚合流游标、回放事实源、背压、NATS 客户端参数 |
| 幂等与 TCC | events-consistency §4–§5 | 异步命令（Jobs.Queue）、Reconciler、工作流引擎对照、读己之写 |
| gRPC 身份 | identity-permissions §5：系统面 | 连接复用、负载均衡、截止时间、重试预算、错误模型、大小、压缩、流式、版本 |
| BatchGet 上限 | data-layer §5 | 并入错误模型（`ErrorInfo.reason`） |
| 授权缓存 | authz-architecture §4.3 | 并入 §7 的缓存总表 |
| 冷热、分区 | data-layer §3–§4 | 分区 DDL 的锁超时，单例改用 Jobs |

---

## 2. 总框架：基础端口、适配器与一致性测试

### 2.1 什么算端口

满足下面三条的才算端口：

1. 它面向基础设施，或者是跨组件的机制，不是业务；
2. 主流平台确实有多种合理实现，并且现在就能**说出第二个实现的名字**；
3. 换实现时组件代码不用动，只改 SDK 内部的适配器和项目配置。

业务流程本身（订单状态机、补偿顺序）**不是端口**：它是业务逻辑，错了就重写。用户的判据里"业务可重写、基础一次对"正是这条分界线。这样既符合 09 号约定"说不出第二个实现就别抽象"，也满足新判据：基础层的第二个实现都能说出名字。

### 2.2 端口登记表

| 端口 | 组件看到的 API | 今天 | 默认适配器 | 具名备选 | 怎么切换 | 一致性测试 | 状态 |
|---|---|---|---|---|---|---|---|
| Store / Tx | `rt.Store.Tx`、`ReadSnapshot`、`LockKey` | `WithTx(db, role, schema)` | pgdialect（PG ≥ 14） | PG 兼容发行版（人大金仓、瀚高：待实测，见 D5） | 无代码改动；方言差异收进 pgdialect | `conformance/store` | 本文 §3 + data-layer |
| EventBus | `rt.Publish(ctx, tx, ev)`、`Module.Events` | NATS 核心 | JetStream | PG 队列（`be_bus` schema）、Kafka | `EVENT_BUS_URL` 的 scheme | `conformance/bus` | 本文 §6 |
| Jobs | `Module.Jobs`、`Module.Workers`、`rt.Enqueue(ctx, tx, …)`、`Reconciler` | 12 份手写 ticker | 原生 PG 表 | 只作参考，不作适配器：River（只有 Go）、DBOS | — | `conformance/jobs` | 本文 §9 |
| RPC（系统面） | `rt.Conn(dep, port)` + 生成的 stub | 每次调用现拨、裸 grpc-go | grpc-go，连接复用 | connect-go 服务端（线协议兼容 gRPC） | 服务端换 handler，客户端不变 | `conformance/rpc` | 本文 §5 |
| UserAPI（REST） | `besdk.GET(r, path, perm, h)`、`rt.UserHTTP(dep)` | Gin，错误体只有 `{"error": msg}` | Gin + problem+json | — | — | `conformance/userapi` | 本文 §5 |
| Cache | `besdk.NewCache` | 无（各写各的） | 进程内 LRU + TTL | 不建 Valkey | — | `conformance/cache`（容量、TTL、失效） | 本文 §7 |
| Edge | `assembly.yaml` 的 `edge_routes` | 声明了但没人读 | Traefik file provider | K8s Ingress / Gateway API、nginx | be-ops 输出不同的生成器 | 黄金路由表 + 端到端 | 本文 §8 |
| Telemetry | `rt.Tracer` / `rt.Meter` / `rt.Logger` | 只有 trace，不传播 | OTLP | — | `OTEL_BASE_URL` | `conformance/telemetry`（传播） | 本文 §5.4、§10 |
| ObjectStorage | `rt.Config.S3URL()` | S3 API | RustFS | MinIO、S3、OSS | `S3_URL`（0106 已定） | `conformance/s3`（D4 冻结存储） | data-layer |
| AuthzProvider | `Access` API | infra/authz | infra/authz | authz-static、authz-openfga | 共享变量 `AUTHZ_URL` | `be-acceptance/authzconf` | authz-architecture |
| IdentityProvider | JWKS 验签 | iam-casdoor | iam-casdoor | keycloak（`resources.tsv:10`） | `IAM_JWKS_URL` | token 黄金向量 | identity-permissions |

### 2.3 一致性测试怎么组织

- 位置：`tools/be-acceptance/conformance/<port>/`。每个套件分两层：
  - **语义向量**：JSON 黄金用例，Go 和 Python 两个 SDK 必须算出相同结果；
  - **适配器黑盒**：真实基础设施，用 `testcontainers` 或 `make up` 起的实例。
- 每个适配器在 CI 矩阵里跑一遍同一套用例。适配器没有声明的能力，套件要断言它会**明确报错或降级**，不许静默。
- 套件本身先跑红：对一个故意写坏的假适配器跑一次，红了才信它的绿（06-testing"新门禁先见一次红"）。

### 2.4 适配器怎么选

运行期由一个共享地址键的 URL scheme 决定，比如 `EVENT_BUS_URL=nats://…` 或 `postgres://…?schema=be_bus`；没有这个键就回退到旧键。组件不 import 任何适配器包；适配器都编译在 SDK 里，按 scheme 注册。外壳里整个进程只有一份适配器，**每个成员一个句柄**（§10）。

---

## 3. 议题一：本地事务

### 3.1 现状与证据

**SDK**

- `WithTx(ctx, db, role, schema, fn func(*sql.Tx) error)`（`be-sdk-go/tx.go:20-50`）：
  - `db.BeginTx(ctx, nil)`（:32）用的是库默认隔离级别 READ COMMITTED；
  - 先 `SET LOCAL ROLE`（:38），再 `SET LOCAL search_path TO <schema>, <schema>_archive`（:42-43）；
  - 不设任何超时，不重试；
  - fn 不接 ctx，事务里能做什么全凭自觉。
- 消费路径又写了一份同样的事务开头（`events.go:104-119`），等于两份代码。Python 的 `with_tx`（`besdk/tx.py:16-61`）同构；asyncpg 的池在归还连接时会 `reset()`（同文件注释 :31-46）。
- 池：
  - Go 没有上限（`standalone.go:79`、`shell/run.go:113`）。database/sql 默认 MaxOpenConns=0（不限）、MaxIdleConns=2，所以高峰过后连接反复建、拆。
  - Python 默认 10（asyncpg 的 min=max=10）。

**组件：写对了的地方，要保留**

| 场景 | 做法 | 证据 | 为什么在 RC 下正确 |
|---|---|---|---|
| 防超卖 | 判定和加锁放在同一条条件 UPDATE 里 | `erp/inventory/backend/internal/repo/reservation.go:74-79`、`movement.go:166-177` | PG 在 RC 下会对被并发修改的行重新求值 WHERE（EvalPlanQual） |
| 已用额度 | `UPDATE … RETURNING` | `erp/finance/backend/internal/repo/credit.go:74`（`applyCreditExposureDeltaTx`） | 同上，原子累加 |
| 凭证号无缺口 | 锁住该法人从业务日期起的全部期间（`FOR UPDATE ORDER BY start_date`），用这把锁分配 `post_no` | `period.go:137-146`、`entry.go:89-118` | 顺序固定，不会死锁；先认领再编号，重复的那次不占号 |
| 队列认领 | `FOR UPDATE SKIP LOCKED` | outbox `be-sdk-go/outbox.go:109-125`，workflow `repo/overdue.go:21-33`，iam `repo/webhookdeliveries.go:79-98` | — |
| 确认链 | 网络调用都在事务外，只有第 ⑤ 步开事务 | `erp/sales/backend/internal/tcc/confirm.go:35-89`、`repo/write.go:150-210` | — |

**组件：事务里做网络调用（违反 02-backend 的规则）**

| 位置 | 情形 | 持有什么 | 最长多久 |
|---|---|---|---|
| sales `consumer.go:85-99` → `tcc/credit_rejected.go:56-79`（**新发现**） | 挂起订单之后调 workflow 的 `CreateTask` | 消费事务 + 订单行锁（`repo/suspend.go:41`） | 5 s（`module.go:31`） |
| sales `consumer.go:183-209` | 赢单转订单：BatchGet、Reserve、建待办 | 消费事务（再加 handler 自己的事务） | 多次调用的超时之和 |
| im-dingtalk `consumer/consumer.go:106-165` | 调钉钉发消息 | 消费事务 | 钉钉 HTTP 超时 |
| iam `service/service.go:226-233` | 登录时调 `ResolveClaims` | 不在事务里，但**没有截止时间** | 无上限 |

### 3.2 缺口与 bug

| # | 缺口 | 后果 |
|---|---|---|
| T1 | 没有 statement / lock / idle / transaction 超时 | 一条慢查询，或者一个忘了提交的事务，能无限占着锁。分区 DDL（`partition.go:85-110`）用的是 `CREATE TABLE … PARTITION OF`，要在父表上取 ACCESS EXCLUSIVE 锁；它一旦排在某个长事务后面，**之后所有对这张表的读写都要排在它后面**（PG 的锁队列），表面看就是整个组件卡死 |
| T2 | 遇到 40001 / 40P01 不重试 | 死锁、序列化失败直接变成 500 或 Internal |
| T3 | 加锁顺序不固定 | 多品预留会死锁（§0.1 第 6 条） |
| T4 | 事务里做网络调用（3 处，见上表） | 锁持有时间等于下游延迟；JetStream 接入后，AckWait 到期还会触发重投 |
| T5 | 池要么无上限、要么太小，同时又有嵌套事务 | 无上限时，一个成员拖垮全体；设了上限以后，"一个 goroutine 同时占两条连接"就会池饥饿死锁 |
| T6 | 选不了隔离级别和只读快照 | 报表要多条查询看到同一时刻。比如 AR 汇总（`arledger.go:163-169`）加明细，在 RC 下两条查询看到的是两个时刻 |
| T7 | **外壳里角色级设置不生效** | PG 的 `ALTER ROLE … SET` 只在登录时生效，`SET ROLE` 不会套用目标角色的设置。外壳以 `shell_<name>` 登录、再 `SET LOCAL ROLE` 切到成员，所以"给成员角色配默认超时"的做法在外壳里静默失效。超时只能由 SDK 在每个事务里 `SET LOCAL` |
| T8 | advisory 锁没有规范 | 今天只出现在提议里（events-consistency 的兼容层、data-layer 的生命周期任务）。键怎么取、用会话级还是事务级都没写。会话级 advisory 锁在连接池里会泄漏给下一个借用者，也和 pgbouncer 的事务池不兼容 |
| T9 | 长事务没有规范 | 回填、冻结导出、批量重算没有"分批提交"的写法 |

### 3.3 市场做法

| 系统 | 默认隔离级别 | 并发控制 | 冲突时 |
|---|---|---|---|
| Odoo | REPEATABLE READ | 行锁；序列化失败交给框架 | 框架遇到 40001 / 40P01 / 55P03 时整请求重试（最多 5 次） |
| ERPNext / Frappe | MariaDB REPEATABLE READ | `for_update` | 死锁直接报错 |
| SAP S/4 | 库层 RC，另有 enqueue 逻辑锁服务 | 逻辑锁（相当于 advisory 锁）+ 更新任务 | 锁冲突直接提示用户 |
| CockroachDB / Spanner 风格 | SERIALIZABLE | 乐观并发 | 客户端必须写重试循环 |
| PG 上常见的 OLTP 写法 | RC | 条件 UPDATE、行锁、约束 | 只在显式用 SERIALIZABLE 时重试 |

方案：

- **(A)** RC + 显式锁（今天的做法，补上超时、重试和加锁顺序）；
- **(B)** RR + 全局重试（Odoo）；
- **(C)** SERIALIZABLE + 全局重试。

本项目有两类热点行：`inventory_balances`（每个 SKU × 仓库一行）和 `accounting_periods`（每个法人一组）。

- 在 PG 的 RR 和 SERIALIZABLE 下，并发更新同一行会直接报 40001，不会像 RC 那样重读最新行。热点上的中止率高，用户感受到的是重试带来的延迟。
- (A) 最适合 PG 上带热点的 ERP 写法。

**选 (A)**，并允许单个事务按需选择 (B) 或 (C)。

### 3.4 推荐设计

**API（Go；Python 同形，snake_case）**

```go
type Isolation int // ReadCommitted（默认）| RepeatableRead | Serializable

type TxOptions struct {
    Isolation        Isolation
    ReadOnly         bool
    StatementTimeout time.Duration // 0 = 5s；取它与 ctx 剩余时间的较小值
    LockTimeout      time.Duration // 0 = 2s
    IdleTimeout      time.Duration // 0 = 30s（idle_in_transaction_session_timeout）
    MaxAttempts      int           // 0 = 3；只对 40001 / 40P01 重试
}

// fn 拿到的 ctx 带"在事务里"的标记；SDK 的出站调用看到这个标记就拒绝（见下）。
func (s *Store) Tx(ctx context.Context, opt TxOptions, fn func(ctx context.Context, tx *sql.Tx) error) error
// 报表用：RepeatableRead + ReadOnly + StatementTimeout 30s，多条查询看到同一快照。
func (s *Store) ReadSnapshot(ctx context.Context, fn func(ctx context.Context, tx *sql.Tx) error) error
// 只提供事务级 advisory 锁；键 = (hash(组件 ID), hash(name|parts…))，外壳里成员之间不会撞键。
func LockKey(ctx context.Context, tx *sql.Tx, name string, parts ...string) error
func TryLockKey(ctx context.Context, tx *sql.Tx, name string, parts ...string) (bool, error)
```

**行为**

1. **超时**：每个事务开头执行 `SET LOCAL statement_timeout / lock_timeout / idle_in_transaction_session_timeout`。服务端 ≥ 17 时，再按 ctx 剩余时间设 `transaction_timeout`（由 pgdialect 探测版本）。用 SET LOCAL，所以外壳里也生效（T7），并且提交或回滚后自动复原。
2. **重试**：
   - 40001、40P01：回滚，等 `10ms·2^n ± 抖动`，用新事务重跑 fn。
   - fn 只碰 tx，所以重放是安全的；"不许走网络"的守卫保证了这一点。
   - 记指标 `besdk_tx_retries_total{reason}`。
   - 不重试的错误码：55P03（锁超时）映射成 `Aborted` + `ErrorInfo.reason=LOCK_TIMEOUT`；57014（语句超时）映射成 `DeadlineExceeded` + `STATEMENT_TIMEOUT`。由调用方带着同一个幂等键，在更高一层决定要不要重试。
3. **事务内不许走网络**：
   - SDK 的 gRPC 客户端拦截器、`UserHTTP`、Bus 直接发布、`rt.Enqueue` 之外的出站调用，看到 ctx 带"在事务里"标记时，一律返回 `ErrNetworkInTx`（测试构建里直接 panic）。
   - 在事务里要触发对外动作，只有两条路：`rt.Publish(ctx, tx, ev)` 进 outbox，`rt.Enqueue(ctx, tx, …)` 进作业队列。
   - fn 的参数也叫 `ctx`，会遮住外层的 ctx，所以按惯用名写代码时守卫自动生效。门禁再补一条：传给 `Tx` 的闭包里，不许引用外层 ctx 的别名。
4. **嵌套事务**：ctx 已经带事务标记时，再调 `Store.Tx` 就返回 `ErrNestedTx`。消费 handler 的 `Apply` 拿到的是同一个 tx。规则是"一个 goroutine 同时最多占一条连接"，这是池饥饿的根治办法。
5. **加锁顺序**：一个事务要锁多行时，按主键或业务唯一键的固定顺序加锁。库存预留先把明细按 `(warehouse_id, product_id)` 排序，重复项提前拒绝。重试只是兜底，不能当成规则。
6. **隔离手段阶梯**（写进 foundations，按顺序优先选前面的）：
   - **约束**：唯一部分索引、排除约束（"同一产品的价目表有效期不重叠"）；
   - **条件 UPDATE**：库存、额度；
   - **排序行锁**：期间、多品；
   - **事务级 advisory 锁，加在逻辑键上**：没有天然可锁的行时，比如"同一客户的信用重算串行"；
   - **SERIALIZABLE + 重试**：跨多行的不变量，前面四种都表达不了时才用。
7. **各领域的落点**：
   - 库存：RC + 条件 UPDATE + 排序；
   - 账簿：RC + 期间行锁 + 事务内校验借贷平衡，报表用 `ReadSnapshot`；
   - 信用：finance 的原子累加是权威，sales 的预判只作参考；
   - 编号：无缺口的用行锁做串行点，允许缺口的用 sequence。
8. **长事务**：
   - 消费 `Apply` 期望 ≤ 1 s，超过就记 Warn 和指标；
   - 回填、冻结、批量操作每个事务 ≤ 1000 行；
   - 迁移里的 DDL 设 `lock_timeout=5s` 并重试；
   - 建分区改成"先 `CREATE TABLE (LIKE …)`，再 `ATTACH PARTITION`"，父表上只取 SHARE UPDATE EXCLUSIVE，并交给 data-layer 的 SDK 分区任务去做。
9. **池与舱壁**：
   - 新增组件配置键 `PG_POOL_MAX`（默认 10）。SDK 设 MaxOpen = `PG_POOL_MAX`、MaxIdle = MaxOpen/2、ConnMaxLifetime = 30 min、ConnMaxIdleTime = 5 min。
   - 外壳用自己的 `PG_POOL_MAX`，默认是各成员之和，并有上限。另外给**每个成员一个容量为它自己 `PG_POOL_MAX` 的信号量**：等待超过 ctx 截止时间就返回 `ResourceExhausted`。一个成员耗尽，不影响别的成员。
   - Python 同理：asyncpg 的 max_size 取同一个键。
10. **pgbouncer**：SET LOCAL ✓，事务级 advisory 锁 ✓；预编译语句需要 pgbouncer ≥ 1.21 并配 `max_prepared_statements`；会话级锁 ✗。写进 02-database。

### 3.5 可替换性

Store/Tx 是一个端口，适配器是 pgdialect。它的范围只到"PG 方言族"（data-layer §2.7、D5）：换成非 PG 的库，要按组件移植 repo 层，不算"简单修改"，文档里要明说。一致性套件 `conformance/store/` 在 PG 14 / 16 / 17 上各跑一遍，人大金仓、瀚高等实测时再加入矩阵。

### 3.6 先写的红测试

be-sdk-go（真 PG；Python 用同名）：

- `TestTx_事务里能看到默认statement_timeout与lock_timeout`（今天红：`SHOW statement_timeout` 是 0）
- `TestTx_ctx剩余时间小于默认时用剩余时间`
- `TestTx_Serializable写偏斜时自动重试且业务效果只生效一次`
- `TestTx_死锁40P01自动重试后成功`
- `TestTx_锁超时映射为Aborted与LOCK_TIMEOUT`
- `TestTx_事务内发起gRPC调用返回ErrNetworkInTx`（今天红）
- `TestTx_嵌套事务返回ErrNestedTx`
- `TestTx_提交和回滚后SET_LOCAL设置不留在池连接上`（池大小 1）
- `TestTx_外壳登录角色SET_LOCAL_ROLE后不套用成员角色的ALTER_ROLE设置`（固定 T7 这个事实，今天绿）
- `TestLockKey_外壳里两个成员同名锁互不阻塞`
- `TestPool_外壳里一个成员耗尽连接预算不影响另一个成员`（今天红）

组件：

- erp/inventory：`TestReserve_两单反序预留同两个SKU并发不报死锁`（用屏障逼出交错；今天红）
- erp/sales：`TestCreditRejected_挂起订单期间workflow慢不阻塞同单取消`（假 workflow 延迟 3 s，取消应在 500 ms 内完成；今天红）
- erp/finance：`TestARSummary_汇总与明细在同一快照`

### 3.7 foundations 文档大纲：`04-local-transactions.md`

- **Scope**：一个组件、一个 PG 事务里的全部规则；不讲跨组件一致性（链到 05）。
- **Choice**：
  - RC 默认 + SDK 每个事务 SET LOCAL 三个超时；
  - 40001 / 40P01 自动重试；
  - 隔离手段阶梯；
  - 排序加锁；
  - 只用事务级 advisory 锁，键带组件 ID；
  - 事务内禁止网络调用，运行期守卫；
  - 不许嵌套事务；
  - 每成员一份连接预算。
- **Port contract**：`Store.Tx` / `ReadSnapshot` / `LockKey` 的签名和语义（重试只针对哪些错误码，错误码怎么映射）。
- **Alternatives**：三列对照 RC+锁 / RR+重试（Odoo）/ SERIALIZABLE（Cockroach），再加 SAP 的 enqueue。
- **Why this choice**：PG 在 RC 下的 EvalPlanQual 让条件 UPDATE 成立；热点行在 RR / SER 下中止率高。
- **Why not the others**：同上，加上"全局重试会把带外部副作用的 handler 跑两遍"。
- **When to switch**：只有出现前四级手段都表达不了的跨行不变量时，才在那一个事务里开 SERIALIZABLE。默认级别不改。
- **How to switch**：`TxOptions.Isolation`，一行。
- **Conformance tests**：§3.6 的 SDK 用例清单。
- **Decision records**：新增"事务内不走网络"、"隔离与重试策略"两条决策（§11.3）。
- **Known limits**：
  - 凭证过账在每个法人上串行（吞吐上限，需要拍板，§13 Q5）；
  - 只承诺 PG 方言族。

---

## 4. 议题二：跨组件一致性

### 4.1 现状：今天用到的几种机制

| 场景 | 机制 | 证据 |
|---|---|---|
| 订单确认 ↔ 库存 | 同步 TCC 编排 | `erp/sales/backend/internal/tcc/confirm.go:35-89` |
| 订单 → 应收与额度 | 事件编舞，finance 回发 `credit.rejected` | `erp/finance/backend/internal/repo/autoentry.go:60-100`；sales `consumer.go:75-102` |
| 赢单 → 订单 | 事件编舞，内部再走 TCC | sales `consumer.go:192-209` |
| 待办完成 → 订单恢复 | 事件编舞 | sales `consumer.go:36,159` |
| 通知 → IM 渠道（族） | 事件编舞 | im-dingtalk `consumer.go:44` |
| 主数据 → 各快照 | 事件 + 计划中的读穿透 | events-consistency §3 |

已经定下的（不重复）：outbox + JetStream、两种 handler（Apply 和 Run）、命令幂等表、`CONFIRMING` 状态、`HoldReservation`、预留 TTL、对账推进。

### 4.2 缺口

| # | 缺口 | 证据 / 后果 |
|---|---|---|
| C1 | **游标按 subject 建键，跨 subject 乱序就出错** | 同一张订单的 `created` 和 `cancelled` 是两个 subject。按 `(subject, aggregate_id)` 建游标时，后到的旧事件仍会被接受。finance 接 `cancelled` 以后，会给已取消的单记应收 |
| C2 | "同一聚合版本"在多个 subject 之间单调递增，只是个隐含约定 | sales 每次写都 `version+1`，并以 `order.Version` 发事件（`repo/write.go:187,202`），所以成立；finance `credit.rejected` 的 Version 恒为 1（`autoentry.go:150`），它其实属于另一个聚合（"信用判定"）。契约里没有声明聚合类型 |
| C3 | 提交之后的"尽力而为"远程调用 | `OpenCreditRejectedTask`（`tcc/credit_rejected.go:20-79`）、补偿失败后开异常待办（`confirm.go:203-207`）。workflow 挂了，这条待办就永远没有，违反了 02-backend"补偿失败三次开异常待办"的本意 |
| C4 | 恢复和推进没有统一的形状 | 请求里 sleep 循环（`confirm.go:172-215`）、只写不读的对账表（`repo/write.go:395-410`）、进程内 goroutine 回查（im-dingtalk `consumer.go:121,192`）、workflow 超期扫描、提议中的预留清扫和 `credit_check_pending`：一共六个，各写各的 |
| C5 | 看不见"卡在半路"的流程 | 没有任何指标能回答"有多少单停在非终态并且已经过期" |
| C6 | 读己之写没有约定 | 确认订单后马上去看应收台账，会读不到；前端不知道这是正常现象 |

### 4.3 市场对照

| | 模型 | 需要的常驻服务 | 语言 | 与本项目约束（单机、每组件一个 schema、外壳、0106） | 可借鉴 |
|---|---|---|---|---|---|
| Seata | AT（undo log + 全局锁）/ TCC / Saga（JSON 状态机）/ XA | TC 协调器（Java） | Java 为主，有 seata-go | AT 要代理数据源、拦截 SQL，和"静态 SQL、无 ORM"冲突；全局锁会把单体式锁竞争带到分布式里；多一个 Java 常驻服务（0105） | TCC 的三类异常：空回滚、幂等、悬挂（我们的 GetStatus 和"先查后补偿"覆盖了前两类；悬挂由预留 TTL 兜底） |
| Temporal / Cadence | 代码即工作流，事件溯源式回放 | 服务端集群 + PG/MySQL/Cassandra（+ 可视化存储） | Go、Python、TS 等都有 | 单机可以跑，但多一套要运维、备份的有状态服务；工作流代码必须确定性，对 AI 是隐形雷区；版本演进要靠 patching | 持久定时器、每步重试策略、按实例可视化的历史 |
| Dapr | sidecar：pub/sub、状态、workflow（durabletask） | 每个应用一个 sidecar | 全语言 | 外壳把 N 个成员合进一个进程，就只能有一个 app-id，成员身份丢失；sidecar 和"无网关、无 mesh"的路线相反 | pub/sub 组件抽象 = Broker 端口；CloudEvents 信封 |
| Axon | 事件溯源 + saga + DeadlineManager | Axon Server（可选） | Java | 不适用 | saga 的期限是一等公民（我们的期限列 + Reconciler） |
| Eventuate Tram | 事务 outbox（轮询或 CDC）+ 消费去重表 + 编排式 saga（命令和回复走消息） | CDC 服务（可选） | Java | 机制和我们最接近 | `received_messages` 去重 ≈ `event_cursor`；saga 实例表 ≈ 业务行状态；命令通道 ≈ 本文的 `Jobs.Queue` |
| DBOS | 库形态的持久化工作流，步骤检查点存在 PG | **无**（库） | Python、TS、Go、Java | 最贴合单机 + PG。**需要验证**能否把它的系统表放进组件自己的 schema、能否和我们的 `Store` 共用事务 | 将来要引擎时的首选候选 |
| Restate | 日志化的持久执行 | 单二进制服务 | TS、Java、Go、Python、Rust | 又多一个常驻服务 | — |

### 4.4 推荐：一致性分五层

| 层 | 内容 | 由谁提供 |
|---|---|---|
| L0 本地 ACID | §3 | Store 端口 |
| L1 事件 | outbox → bus → 消费；effectively-once = 至少一次送达 + **聚合流游标**；handler 分 Apply / Run | EventBus 端口（§6） |
| L2 命令 | 同步：gRPC + 幂等键 + GetStatus（今天就是）；**异步：`rt.Enqueue(ctx, tx, "workflow.create_task", args, UniqueKey)` 在业务事务里入队，SDK 在事务外执行，失败按退避重试，重试用尽进"死信"状态并开异常待办** | Jobs 端口（§9） |
| L3 流程（saga） | 业务行上的状态机 + 期限列（`deadline_at`）+ `Reconciler` 推进或退回；补偿本身也是 L2 命令；超过上限就转 SUSPENDED 并开异常待办（02-backend 已有规则） | 业务代码 + Reconciler 帮手 |
| L4 人 | workflow 待办、DLQ 工具（E13） | infra/workflow、make 目标 |

**C1 的修法：聚合流游标**

- 事件契约 `contracts/events/*.json` 给每个 subject 声明 `x-aggregate-type`（如 `erp.sales.order`；`infra.notification.dispatch.im.v1` 这类 action 里带点号的，不能靠从 subject 里切字符串得到，只能显式声明）。信封带 `ce-aggregatetype` 头。
- 生产者规则：同一个 `aggregate_type` 的所有 subject 共用一个单调递增的聚合版本（gate 检查事件契约里有这个声明）。
- 消费者游标主键 `(aggregate_type, aggregate_id)`。语义就是 events-consistency 的"状态模式"：较旧的版本跳过。所以 handler 必须写成"把聚合推进到第 v 版的状态"。例如 finance 收到 `cancelled`(v3)：已记账就冲销；还没记账就记一个"已取消未记账"标记。之后 `created`(v2) 被跳过，结果正确。
- 需要"每一次变更都要按序处理"的消费者（序列模式）今天还没有。信封预留 `ce-sequence`（outbox 按聚合计数，与业务 version 分开，因为业务 version 可能在不发事件的更新里也递增）。等第一个这样的消费者出现，再实现"有缺口就 Nak 延迟重投，若干次后读穿透或进 DLQ"。

**Reconciler（Go；Python 同形）**

```go
type Reconciler[T any] struct {
    Name        string                                              // 指标名、租约名
    Every       time.Duration
    Batch       int
    Candidates  func(ctx context.Context, tx *sql.Tx, limit int) ([]T, error) // 组件自己的 SQL：非终态且 deadline_at < now()
    ID          func(T) string
    Handle      func(ctx context.Context, item T) (Outcome, error) // 在事务外，可以走网络（幂等键要从 item 确定性派生）
    Apply       func(ctx context.Context, tx *sql.Tx, item T, out Outcome) error // 组件自己的 SQL：锁行、重新检查状态机、推进
    MaxAttempts int
    Backoff     []time.Duration
    GiveUp      func(ctx context.Context, tx *sql.Tx, item T) error // 置 SUSPENDED + rt.Enqueue("开异常待办")
}
```

SDK 用一张侧表 `besdk_reconcile(name, item_id, attempts, next_at, lease_until, last_error)` 做租约和退避，业务表不用加通用列。每轮的流程：

1. 取候选；
2. 逐个原子认领（`INSERT … ON CONFLICT DO UPDATE … WHERE lease_until < now() AND next_at <= now() RETURNING`）；
3. 执行 `Handle`；
4. 在短事务里执行 `Apply`；
5. 进入终态就删掉侧表行，否则 `attempts+1` 并设下一次时间。

指标：

- `besdk_reconcile_pending{name}`
- `besdk_reconcile_oldest_age_seconds{name}`
- `besdk_reconcile_giveups_total{name}`

这三个指标就是 C5 要的"卡在半路"视图。

用户（六个）：

- sales 的 CONFIRMING 推进 / 退回、`hold_pending`、`release_pending`；
- inventory 的过期预留清扫；
- finance 的 `credit_check_pending`；
- im-dingtalk 的 `ACCEPTED` 回查；
- workflow 的超期扫描；
- iam 的 webhook 投递。

### 4.5 要不要可替换的"工作流引擎"适配器

**结论：现在不建引擎端口；把引擎提供的基础能力（持久定时、租约、重试、幂等命令、升级给人）做成端口，即 Jobs 和 Reconciler。**

1. 不同引擎定义流程的方式根本不同：Temporal 是确定性代码，DBOS 是带装饰的步骤，我们是状态表。换引擎就要重写编排代码，不满足"简单修改即可切换"。硬说它是端口，是假承诺。
2. 编排本身是业务逻辑，按用户的判据可以重写。基础那一半已经端口化，并且可以在下面换实现，比如将来用 DBOS 驱动 `Jobs.Queue`。
3. 写死两条不变量，保证将来换引擎时对其他组件透明：
   - 流程只活在**发起它的组件里**，没有中央编排组件；
   - 流程状态就是业务行，对外只通过 `GetStatus` 和事件暴露。
4. **切换条件**：出现一个跨 ≥ 3 个组件、≥ 5 步、含按天计的人工等待，并且需要按实例看历史或给运行中的实例做版本迁移的流程（采购到付款、项目里程碑结算）。届时先评估 DBOS（库形态、PG 原生、单机），后评估 Temporal（要接受集群运维）。

**为什么用户面向的步骤保留同步 TCC，而不是 Tram 式的异步命令**：用户点"确认"时要立刻知道"库存不足"。异步命令需要前端轮询，交互更差。所以规则是：用户等待结果的步骤走同步，后续的副作用走 L2 异步命令。

### 4.6 读己之写（前端预期）

1. **同一组件内**：写后立即读一致。命令响应返回新状态和 `version`，前端用响应直接更新本页，不需要立刻重新查询。
2. **跨组件的派生视图**（应收台账、商机上的订单号、通知、授权投影）：最终一致。
   - 每个消费者暴露 `besdk_consumer_lag_seconds{subject}`。
   - 派生视图的 List / Get 可以返回响应头 `X-Data-As-Of`：这个投影最近处理完的事件的 `occurred_at`。
   - 前端的场景是"刚写完就跳到派生视图"：时间早于本次写操作就显示"同步中"，自动重查一次，最多等 10 秒。
3. **必须强一致的展示**（确认后立刻显示的可用库存）：去问属主（同步调用），不读投影。
4. authz 的一致性令牌（authz-architecture §3.7）是同一机制的特例。

### 4.7 先写的红测试

- be-sdk-go：
  - `TestEventCursor_同一聚合不同subject共用版本游标`（按 events-consistency 的表结构跑，红）
  - `TestReconciler_两个副本同一行只处理一次`
  - `TestReconciler_Handle失败按退避重试达到上限调用GiveUp`
  - `TestReconciler_进程在Handle后Apply前崩溃下一轮续跑`
  - `TestEnqueue_业务事务回滚时命令不执行`
  - `TestEnqueue_UniqueKey重复入队只执行一次`
- **通用属性测试模板**（每个消费者都要有一条，写进 06-testing）：`Test<Consumer>_乱序与重复投递的终态等于按序投递`。用 rapid 对一组事件做随机打乱和重复，断言最终状态等于按序处理一次的结果。
- erp/finance：`TestOrderCancelled先于Created到达_不记应收`。
- erp/sales：
  - `TestCreditRejected_workflow不可用时异常待办在恢复后被建出`（今天红：尽力而为丢了）
  - `TestCompensation_进程重启后释放预留继续`（今天红：靠请求里的 sleep）

### 4.8 foundations 文档大纲：`05-consistency-across-components.md`

- **Scope**：两个及以上组件之间的状态一致性：事件、命令、流程、补偿、期限、读己之写。
- **Choice**：
  - 五层模型；
  - 聚合流游标（状态模式）；
  - 命令幂等表（events-consistency §1.3）；
  - 同步 TCC 只用于用户等待的步骤；
  - 后续副作用一律走异步命令；
  - 业务行即 saga 日志 + Reconciler；
  - 人工兜底。
- **Port contract**：`Publish` / `EventsSpec` / `Enqueue` / `Reconciler` 的语义（至少一次、幂等键的派生规则、期限）。
- **Alternatives**：§4.3 表格。
- **Why this choice**：没有新增常驻服务；外壳合并安全；状态对人和 AI 都可读。
- **Why not the others**：
  - Seata AT：拦截 SQL、全局锁；
  - Temporal：多一套集群，确定性约束是雷区；
  - Dapr：sidecar 和外壳冲突；
  - 通用 saga DSL：说不出第二个编排形状。
- **When to switch**：§4.5 第 4 条。
- **How to switch**：引擎替代的只是 Reconciler + Jobs 这层驱动；业务状态表与对外契约不变。
- **Conformance tests**：乱序属性测试模板、Reconciler 用例、Enqueue 用例。
- **Decision records**：
  - "流程只活在发起组件里、状态即业务行"；
  - "提交后的远程副作用必须经异步命令"；
  - 修订 events-consistency 落地时写的事件决策（游标键）。
- **Known limits**：序列模式还没实现；跨组件视图只承诺最终一致。

---

## 5. 议题三：同步通信

### 5.1 现状与证据

| 方面 | 今天 | 证据 |
|---|---|---|
| 客户端 | 每次调用 `grpc.NewClient`、insecure、不带任何选项；调用后关闭 | `be-sdk-go/client.go:73-100`；sales `internal/client/client.go:49-66`；opportunity `internal/client/client.go:40-75` |
| 身份透传 | 在拨号时从 gRPC 入站 metadata 取 token；在 REST 路径上什么都取不到 | `client.go:78-87`；identity-permissions §5.1 |
| 截止时间 | sales 每次调用固定 5 s（`erp/sales/backend/module/module.go:31`）；opportunity 可配；iam 无；BFF 无 | 见 §0.1 第 1 条 |
| 服务端 | `grpc.NewServer` 只挂一元 recovery，没有流拦截器、keepalive、显式消息上限、指标、OTel | `standalone.go:215` |
| HTTP 服务端 | 零超时；中间件有 request-id、span、RED 指标、访问日志、错误映射 | `standalone.go:187`；`gin.go:27-76` |
| 错误体 | gRPC status 映射成 HTTP 码，错误体只有 `{"error": msg}`；全仓没有 `google.rpc` 错误详情 | `gin.go:117-167`；grep `errdetails` 为空 |
| trace | 不传播 | grep `SetTextMapPropagator` / `otelgrpc` / `otelhttp` 为空 |
| 流式 | 无（90 个 rpc 全是一元） | grep `stream` 为空 |
| 分页 | 游标（0301）；`ListWindow` 默认 90 天（D3 要去掉） | `be-sdk-go/query.go:298-333` |
| GraphQL | 只在 BFF（graphql-yoga 5.22 + persisted operations + graphql-armor） | `be-sdk-ts/package.json:22-26` |
| K8s | brickKit 为每个组件生成 ClusterIP Service；`replicas>1` 时自动生成 PDB；component.yaml 的 `extraPorts` 只有 `name` / `port`，**没有协议字段** | `11-reference/01-component-yaml-schema`（第 92-93 行）；`01-three-layers/03-deploy-yaml` |
| brickKit 的立场 | "平台不管熔断、重试、退避，那是组件自己的事"；"对依赖设的超时必须短于调用方愿意等你的时间" | `09-patterns/04-service-calling`、`06-architecture/05-design-principles` |

### 5.2 缺口

- R1 没有连接复用：每个请求都要握手；高并发时 TIME_WAIT 堆积。
- R2 没有默认截止时间，也没有预算传递：一个子调用就能吃掉调用方的全部等待时间。
- R3 没有重试，也没有重试预算：一次 `UNAVAILABLE`（brickKit 实测，容器替换的瞬间）直接变成用户可见的错误。
- R4 复用连接之后，K8s 上会钉死在一个 Pod（L4）。
- R5 错误模型只有一句话：前端没法按原因做本地化和分支处理；`BATCH_TOO_LARGE`（D8）没有地方放。
- R6 trace、request-id 不传播。
- R7 HTTP 服务端没有超时（slowloris），也没有请求体上限。
- R8 BFF 的 fetch 没有超时（brickKit 实测：Node 会无限挂起）。
- R9 消息大小靠默认值：gRPC 接收 4 MiB；NATS `max_payload` 8 MB（`infra/nats/nats.conf`）。
- R10 没有出站并发上限：一个慢依赖能把调用方的 goroutine、连接全部占满。
- R11 0103 写的是 Apollo，实际是 Yoga。

### 5.3 协议选型对照

| | gRPC（grpc-go / grpc.aio / grpc-js） | REST + OpenAPI（Gin / FastAPI） | GraphQL（BFF） | Connect-RPC | Twirp |
|---|---|---|---|---|---|
| 契约 | proto，类型强，buf breaking 检查 | OpenAPI，前端类型由它生成 | SDL | proto，与 gRPC 同一份 | proto |
| 浏览器直连 | 否（要 gRPC-Web） | 是 | 是 | 是（HTTP/1.1 JSON） | 是 |
| 流式 | 双向 | 无（SSE 另算） | 订阅 | 服务端流 / 双向（HTTP/2） | 无 |
| 生态（Go / Py / TS） | 都成熟 | 都成熟 | TS 成熟 | Go、TS 成熟，Python 较新 | Go 为主 |
| 截止时间、重试、负载均衡 | 内建（grpc-timeout、service config、round_robin） | 要自己做 | 要自己做 | 截止时间有；重试和负载均衡要自己做 | 无 |
| 网关、调试 | 要 grpcurl | curl 就行，网关路由天然 | 要工具 | curl 就行 | curl 就行 |
| 与外壳 | 一个成员一个端口 | 同左 | — | 可以和 HTTP 共用端口 | 同左 |

**结论**：维持两个面。

- **系统面用 gRPC**：截止时间、重试、负载均衡内建；Python 有 `grpc.aio`；proto 有 additive 检查。
- **用户面用 REST**：前端生成类型；网关按路径路由；人可读。

Connect-RPC 的优势"一份 proto 同时服务浏览器"，正好和"gRPC 是系统面、用户只走 REST"相冲突（identity-permissions §5 的安全边界），所以不引入。connect-go 的服务端能说 gRPC 线协议，把它写成**将来的逃生口**：服务端换 handler，客户端不用改。GraphQL 只留在移动端 BFF。

### 5.4 推荐设计

1. **连接**：`rt.Conn(dep, port)` 返回按成员缓存的 `*grpc.ClientConn`，懒建、复用，Stop 时关闭。拨号选项：
   - keepalive：Time 30 s、Timeout 10 s，不在空闲时发 ping；
   - `WithDefaultServiceConfig`（下面第 5 条生成）；
   - otelgrpc stats handler；
   - 拦截器链：默认截止时间 → 出站并发上限 → metadata（`traceparent` 由 OTel 注入；`x-request-id`；`be-caller` = 本成员 ID；`be-actor-sub` **在每次调用时**从 ctx 读）→ 客户端 RED 指标 → 事务守卫（§3.4）。

   `UserClient` / `SystemClient` 按 identity-permissions 退化成弃用包装。
2. **服务端**：一元和流两条拦截器链：
   - recovery → 身份（identity-permissions）→ 截止时间下限（入站没带 grpc-timeout 时补默认 10 s）→ BatchGet 上限（D8）→ 错误详情规范化 → RED 指标 → OTel。

   其他参数：
   - `MaxRecvMsgSize(4 MiB)` 显式写出；
   - `keepalive.ServerParameters{MaxConnectionAge: 5m, MaxConnectionAgeGrace: 30s}`；
   - `EnforcementPolicy{MinTime: 20s}`。
3. **K8s 负载均衡**：
   - 默认靠服务端的 `MaxConnectionAge` 定期 GOAWAY：客户端重连时被 kube-proxy 重新分配，约 5 分钟内重新均衡。普通 ClusterIP 就够用，Docker 上也没有副作用。
   - 选项：brickKit 能为 grpc 端口生成 headless Service 时（§12 F1），客户端用 `dns:///` + `round_robin`。
   - 不做 xDS / mesh。
4. **截止时间预算**：
   - 入站 HTTP 中间件：ctx 截止时间 = 路由声明值（默认 10 s；导出类路由自己声明）；
   - gRPC 入站：自动取 grpc-timeout；
   - 出站每次调用的超时 = min(3 s, 剩余预算 − 50 ms)；剩余不足 50 ms 直接返回 `DeadlineExceeded`，不发出调用；
   - DB 的 statement_timeout = min(5 s, 剩余预算)（§3.4）；
   - 事件 handler 的截止时间 = AckWait − 余量；
   - Reconciler 每一步自己限时。

   规则原文写进文档："子调用的超时必须短于调用方愿意等你的时间"（brickKit `09-patterns/04-service-calling`）。
5. **重试**：服务配置按 proto 方法选项生成。
   - `option idempotency_level = NO_SIDE_EFFECTS`（读、BatchGet、GetStatus）和 `IDEMPOTENT`（带 `idempotency_key` 的写，由门禁强制标注）的方法：`retryPolicy{maxAttempts: 3, initialBackoff: 50ms, maxBackoff: 500ms, backoffMultiplier: 2, retryableStatusCodes: [UNAVAILABLE]}`。
   - 其他方法只用 gRPC 的透明重试（请求从未发出时）。
   - 全局 `retryThrottling{maxTokens: 10, tokenRatio: 0.1}` 作为**重试预算**：额外流量不超过约 10%，下游大面积故障时自动停止重试。
   - hedging 默认关（单机没有收益）。
   - REST 用户面：`UserHTTP` 只对 GET 在连接被重置时重试一次；前端写操作只用同一个 `Idempotency-Key` 重试。
6. **熔断与舱壁**：不引入熔断库。用三件事替代：
   - 每成员、每依赖的出站并发上限（默认 64，超了立刻返回 `ResourceExhausted`）；
   - 重试预算；
   - 截止时间。

   重开条件：多节点部署下出现"部分实例坏、部分好"的实测故障。届时再考虑拦截器级熔断或 xDS 异常检测。
7. **错误模型**（新决策）：
   - 每个组件有一份 reason 登记表 `contracts/errors.yaml`（`reason` 用 UPPER_SNAKE，`domain` = 组件 ID，只增不改，规则同 permissions.tsv）。
   - gRPC：状态码 + `ErrorInfo{reason, domain, metadata}`，按需附 `BadRequest`、`PreconditionFailure`、`RetryInfo`、`ResourceInfo`。
   - REST：`application/problem+json`（RFC 9457），字段为 `type`（`urn:be:<domain>:<reason>`）、`title`、`status`、`detail`、`instance`、`code`（gRPC 码名）、`reason`、`domain`、`metadata`、`violations[]`、`request_id`、`trace_id`。
   - BFF：GraphQL `extensions{code, reason, domain}`。
   - 业务代码写 `besdk.Errorf(codes.FailedPrecondition, "INSUFFICIENT_STOCK", meta)`；SDK 双向映射（`UserHTTP` 能把 problem+json 还原成 status）。
   - 前端按 `domain:reason` 查 i18n 文案。
   - data-layer 的 `BATCH_TOO_LARGE`、本文的 `LOCK_TIMEOUT`、`IDEMPOTENCY_MISMATCH` 都是这张表里的行。
8. **分页**：沿用游标（0301），形状对齐 AIP-158：`page_size`（有上限）、不透明的 `page_token`（编码排序键、id 和过滤条件哈希，换了过滤条件的 token 返回 `INVALID_ARGUMENT`）、`next_page_token`。不返回精确总数。
9. **流式**：系统契约里不用。大结果走对象存储 + 事件（claim-check）。重开条件：出现实时推送需求。
10. **大小与压缩**：
    - gRPC 两侧都是 4 MiB；BatchGet ≤ 500（D8）；
    - 事件载荷建议 ≤ 64 KiB，硬上限是 NATS 的 8 MB，更大的走 S3 claim-check；
    - 默认不压缩（回环或局域网上压缩是负收益）；超过 1 MiB 的响应可以按调用开 gzip。
11. **版本**：proto 包名 `<domain>.<name>.v1`，只增（0302），`buf breaking` 接进 contract-check；大版本是另起一个 `v2` 包并行服务，按 0302 的 Revisit 走。
12. **服务发现**：用 brickKit 注入的 `*_ENDPOINT`，必须带端口名（`"grpc"`）。不做注册中心。

### 5.5 外壳里

- 成员之间仍然走网络：`*_ENDPOINT` 指向外壳服务名 + 成员端口（brickKit `09-patterns/04-service-calling` 的"Calling a member inside a shell"）。Docker 上解析回本容器，开销约 0.1 ms。不引入进程内传输（bufconn）：它会绕开序列化和拦截器，单跑与合并的行为就不再一致（0101 / 0108）。
- 连接池按成员分开，保证 `be-caller` 是真正的调用方，也让舱壁和并发上限按成员计。
- 自调用风险：A 成员的 handler 同步调 B 成员，两边都要连接。每成员一份连接预算（§3.4 第 9 条）保证 A 的突发不会饿死 B。
- 外壳重启时全部成员一起不可用，调用方会看到同一次抖动（brickKit 已写明）。重试预算加截止时间能吸收它。

### 5.6 可替换性

RPC 端口 = `rt.Conn` + 生成的 stub。线协议是全项目统一的选择，不是组件级的适配器。一致性套件 `conformance/rpc/` 覆盖：

- 截止时间传递；
- 只对幂等方法在 UNAVAILABLE 时重试；
- 重试预算耗尽后停止；
- 错误详情双向映射；
- metadata（traceparent、x-request-id、be-caller、be-actor-sub）传递；
- 消息大小；
- `MaxConnectionAge` 之后重连。

### 5.7 先写的红测试

- be-sdk-go：
  - `TestConn_同一依赖百次调用只建一条连接`
  - `TestConn_未设截止时间的调用获得默认截止时间`
  - `TestHTTP_入站请求有默认截止时间且出站继承剩余预算`
  - `TestRetry_只对NO_SIDE_EFFECTS或IDEMPOTENT方法在UNAVAILABLE时重试`
  - `TestRetry_重试预算耗尽后不再重试`
  - `TestErrors_ErrorInfo映射为problem_json且能还原`
  - `TestTrace_HTTP到gRPC到outbox事件同一trace_id`
  - `TestHTTPServer_慢请求头在ReadHeaderTimeout后断开`
  - `TestGRPCServer_MaxConnectionAge后客户端透明重连`
  - `TestOutboundLimit_超过并发上限立刻ResourceExhausted`

  以上今天全部是红的。
- infra/iam-casdoor：`TestToken_authz挂起时登录在截止时间内失败`（今天红：无限等）。
- infra/bff-mobile：`TestForwardGet_下游挂起时在预算内返回GraphQL错误`（今天红）。
- be-acceptance 门禁：`idempotency-level-scan`，带 `idempotency_key` 字段的 rpc 必须标 `IDEMPOTENT`。按惯例先对一个故意违规的样例跑红。

### 5.8 foundations 文档大纲

**`08-system-rpc.md`**

- **Scope**：组件间的 gRPC：连接、负载均衡、metadata、大小、压缩、流式、版本、外壳内的调用。
- **Choice**：
  - grpc-go / grpc.aio；
  - 按成员复用连接；
  - 用 `MaxConnectionAge` 做负载均衡，headless 作为选项；
  - 不用流式；
  - 4 MiB；
  - 默认不压缩；
  - proto 包版本。
- **Port contract**：`rt.Conn` 的语义、拦截器顺序、metadata 清单。
- **Alternatives**：§5.3 表。
- **Why this choice / Why not the others**：Connect 冲突在安全边界；Twirp 没有截止时间和负载均衡；GraphQL 只适合聚合场景。
- **When to switch**：
  - 浏览器需要直接调 proto（重议 identity 的决定）时，服务端换 connect-go；
  - 多节点时考虑 xDS。
- **How to switch**：服务端换 handler，客户端不变。
- **Conformance tests**：§5.6。
- **Decision records**：0208（gRPC 是系统面）、0304（BatchGet 上限）。
- **Known limits**：L4 负载均衡要几分钟才能重新均衡。

**`09-user-api.md`**

- **Scope**：REST 用户面。
- **Choice**：
  - 路由权限键（02-backend）；
  - problem+json 加 reason 登记表；
  - `Idempotency-Key` 请求头（对齐 IETF httpapi 草案），与 body 里的 `idempotency_key` 等价，进同一个 `Command.Key`；
  - AIP-158 游标分页；
  - `X-Data-As-Of`；
  - 版本策略（OpenAPI additive）。
- **Alternatives**：GraphQL 全量化、Connect、OData。
- **When to switch**：对外开放 API（§13 Q4）。
- 其余小节同模板。

**`10-deadlines-and-retries.md`**

- **Scope**：一条请求从边缘到 DB、RPC、事件、Reconciler 的时间预算与重试。
- **Choice**：
  - 预算公式；
  - 方法级重试只靠 `idempotency_level`；
  - 重试预算；
  - 舱壁；
  - 不用熔断库。
- **Alternatives**：Hystrix / resilience4j 式熔断、Envoy 异常检测、客户端 hedging。
- **When to switch**：多节点部分故障。
- **Conformance tests**：重试、预算、截止时间三组用例。

---

## 6. 议题四：异步消息与队列选型

### 6.1 现状（只列 events-consistency 没写的）

- infra：nats 2.10，已开 JetStream（`infra/docker-compose.infra.yml:49-55`）；`max_payload: 8MB`（`infra/nats/nats.conf`）。
- `infra/resources.tsv:4,11,12`：nats、kafka、rabbitmq 同属互斥组 `mq`。kafka 和 rabbitmq 也各有 compose profile（`docker-compose.infra.yml:173-210`），可是 SDK 没有对应的适配器。
- 客户端参数全用默认：MaxReconnects 60 × 2 s；不开 RetryOnFailedConnect（NATS 晚于组件就绪时，组件启动就失败）；没有设 Name、断线 / 错误回调。
- 核心订阅的回调对每个订阅串行执行：sales 赢单 handler 一跑十几秒，同 subject 的后续消息全部排队，超过 pending 上限就被**静默丢弃**（没有异步错误回调）。JetStream pull 能根治，迁移前写清楚。
- SDK 内部用 `slog.Default()` 记消费失败（`events.go:69`），在外壳里丢了成员 ID。

### 6.2 选型对照

| | NATS JetStream | Kafka（KRaft） | Redpanda | RabbitMQ（quorum queue / stream） | Pulsar | PG 队列（pgmq / River / Graphile Worker / pg-boss / 自研表） |
|---|---|---|---|---|---|---|
| 单机资源 | 单个 Go 二进制，几十 MB | JVM，GB 级 | C++ 单二进制，内存偏大 | Erlang，中等 | 多组件，重 | 零新增（复用 PG） |
| 持久与回放 | 流按时间 / 大小保留，可从任意时间点重放 | 日志保留，按 offset 重放 | 同 Kafka | stream 可以；queue 消费即删 | 分层存储 | 表即日志，保留期自定 |
| 顺序 | 流内有序；重投会打乱 | 分区内有序；重平衡、重试会打乱 | 同 Kafka | 单队列有序 | 分区有序 | 按 id 有序；SKIP LOCKED 会打乱 |
| 竞争消费 / 重投 / DLQ | durable + Nak 退避 + MaxDeliver；DLQ 自己做 | 消费组；重投与 DLQ 靠重试 topic 模式 | 同 Kafka | 原生 DLX、TTL、延迟 | 原生 | 自己做（简单） |
| 去重 | `Nats-Msg-Id` 时间窗口 | 幂等生产者（只在生产侧） | 同 | 无 | 有 | 唯一键 |
| 客户端（Go / Py / TS） | 都成熟 | 都成熟 | Kafka 客户端 | 都成熟 | Go、Py 一般 | River 只有 Go；pgmq 要装扩展（和"PG 兼容发行版"、最小权限冲突）；Graphile / pg-boss 只有 Node |
| 吞吐上限 | 单机十万级消息/秒 | 百万级 | 百万级 | 万到十万级 | 百万级 | 千到万级（受 PG 写放大限制） |
| 与本项目 | 已部署、单机、多租户账号、核心 NATS 兼顾 poke | 过重（0105 的精神） | 资源仍偏大 | 能用，但流语义弱、回放差 | 过重 | 适合最小安装、测试、组件内作业 |

**结论**：

- JetStream 作为默认（与 events-consistency 一致），理由：已部署；单机轻；流 + durable + Nak 退避 + 去重窗口正好覆盖我们要的语义；核心 NATS 还顺带承担 authz poke 这类即时信号。
- PG 队列是**第二个适配器**：零新增依赖，适合"只有一台小机器、不想多跑 NATS"的客户和测试替身，也用来证明端口真的可换。
- Kafka 适配器等客户自带 Kafka 时再建。
- RabbitMQ、Pulsar 不建。`resources.tsv` 里的 kafka、rabbitmq 行先删掉，或者标成"无 SDK 适配器，不可用"。

### 6.3 推荐设计

1. **顺序的立场**（写进 07-event-contracts）：**正确性永远不依赖 broker 的顺序**。消费者靠聚合流版本对乱序免疫（§4.4）；broker 的顺序只影响性能（少几次跳过）。需要严格按序的消费者走序列模式（预留，未实现）。
2. **按聚合分区**：正确性上不需要。只有实测吞吐要求"多实例并行、同一聚合仍有序"时，才用 JetStream subject mapping 的 `partition(n, …)` 拆成 `<subject>.<p>`，每个分区一个 durable，MaxAckPending=1。
3. **回放**：
   - 流的保留期（7 天）以内：新建一个从指定时间开始的临时消费者。
   - 超过保留期：`make events-replay COMPONENT=… SUBJECT=… SINCE=…` 从**生产者的 outbox 表**读出来重发（Msg-Id 加后缀，避开去重窗口）；消费者靠游标去重。
   - outbox 的在线保留期 ≥ 30 天（并入 data-layer 的 lifecycle.yaml）。这样回放不依赖具体 broker。
4. **信封用 CloudEvents 1.0 的二进制模式**（NATS 和 Kafka 绑定都把属性放在头里）：
   - `ce-specversion=1.0`
   - `ce-id` = event_id（同时作为 `Nats-Msg-Id`）
   - `ce-source` = 组件 ID
   - `ce-type` = subject
   - `ce-time` = occurred_at
   - `ce-subject` = aggregate_id
   - 扩展：`ce-aggregatetype`、`ce-aggregateversion`、`ce-causationid`、`ce-hopcount`、`ce-dataschema`（契约文件路径 @ 组件版本）
   - 加上 `traceparent`

   读取时兼容旧的 `X-Aggregate-Id` 等头（`events.go:28-33`）。这一条改的只是 events-consistency §1.1 的头名，字段不变，要在 be-sdk v0.6.0 发布前定下来。
5. **schema 演进与登记**：
   - `contracts/events/*.json` 加 eventsbreaking 门禁，这就是登记处；不上 Confluent 式的运行期 schema registry。
   - 契约新增 `x-aggregate-type`、`x-consumption: state|sequence`。
   - 消费者宽松读取：未知字段忽略，缺少的可选字段取默认值。
6. **DLQ**：沿用 events-consistency（`dlq.<durable>.<subject>`、30 天、E13 的 make 目标），另加 `besdk_dlq_messages_total{subject,consumer}` 和告警规则模板。
7. **不承诺"恰好一次"**：
   - JetStream 的"exactly once"（去重窗口 + 双重 ack）只消除窗口内、broker 与客户端之间的重复。
   - 我们库里的效果靠"同一事务推进游标"做到 effectively-once。
   - 外部副作用（钉钉）是至少一次，靠业务键做幂等。
8. **背压**：
   - 消费侧：pull `Fetch(batch, expires)`；每个 durable 的 MaxAckPending 默认 256；每个订阅的并发默认 4，同时受成员 DB 预算约束。
   - 生产侧：outbox pump 异步发布，最多 256 个 PubAck 在途；轮询间隔自适应（忙时 200 ms，空闲时逐步退到 2 s，减轻外壳里 N 个成员 × 5 次/秒的空转）。
   - 域流用 `discard=old` 加 1 GiB 上限：离线很久的消费者会丢事件，这是有意的取舍（有 outbox 回放兜底）。所以要有告警：消费者 lag 或 `num_pending` 接近上限时报警。
9. **客户端参数**：`MaxReconnects(-1)`、`ReconnectWait(2s)` + 抖动、`RetryOnFailedConnect(true)`、`Name(<成员 ID>)`；断线、重连、错误回调都用成员的 logger 记录。外壳里共享一条连接（订阅名带成员 ID）。
10. **即时信号**：authz 的 `changed` poke 这类信号走端口的 `Notify / OnNotify`（尽力而为，可以丢）。PG 适配器用 LISTEN/NOTIFY 实现，Kafka 适配器用一个短保留的 topic 实现。

### 6.4 Broker 端口与一致性套件

```go
// SDK 内部端口；组件只看到 rt.Publish(ctx, tx, ev) 与 Module.Events（events-consistency §2.4）
type Bus interface {
    EnsureStream(ctx context.Context, s StreamSpec) error // 没有就建、有就不碰
    Publish(ctx context.Context, m Message) error          // m.ID 用于去重；返回 nil 表示已持久化
    Consume(ctx context.Context, c ConsumerSpec, h func(ctx context.Context, d Delivery) error) error
    Notify(ctx context.Context, subject string, data []byte) error
    OnNotify(ctx context.Context, subject string, h func([]byte)) error
}
type Delivery interface {
    Message() Message
    NumDelivered() int
    Ack() error; Nak(delay time.Duration) error; Term(reason string) error; InProgress() error
}
```

适配器：

- **jetstream**（默认）。
- **pgqueue**：
  - 表放在基础设施专属的 `be_bus` schema（由 `make db-init` 建，各组件角色只授 INSERT / SELECT / UPDATE）；
  - 流 = 按时间分区的消息表 + 保留期；
  - durable = 一行 offset，加上"在途 / 重投"表（SKIP LOCKED）；
  - Notify = LISTEN/NOTIFY。
  - 它和 NATS 一样属于基础设施，不违反 0102（组件之间仍然不读对方的 schema）。
- **kafka**（按需）：一个流一个 topic，一个 durable 一个消费组；Nak 延迟用重试 topic 模拟；DLQ 用 topic。

选择方式：新增共享键 `EVENT_BUS_URL`（`nats://`、`postgres://…?schema=be_bus`、`kafka://`），没有时回退 `NATS_URL`。0106 的"Swap NATS for Kafka by a setting"改写成"不是一个开关，而是一个 SDK 适配器加上 URL scheme；适配器要通过一致性套件才算支持"。

`conformance/bus/` 用例：

- 消费者重启后收到离线期间的消息
- 同一 durable 的两个实例每条只处理一次
- Nak 按退避重投
- 超过 MaxDeliver 进 DLQ 并带原因
- `Term` 不再重投
- 同一 ID 在窗口内只持久化一条
- EnsureStream 幂等且不覆盖已有配置
- 处理慢时 InProgress 防止重投
- 头字段往返不丢
- 超过载荷上限明确报错
- 单一消费者在无故障时按发布顺序收到
- Notify 不持久、不重投
- 外壳里两个成员订阅同一 subject 各收一份

### 6.5 先写的红测试

- be-sdk-go：
  - `TestNATS_服务端停机三分钟后自动重连并恢复订阅`（今天红）
  - `TestNATS_启动时服务端未就绪会等待而不是退出`（今天红）
  - `TestConsume_慢handler不阻塞同组件其他subject`（今天红）
  - `TestConsume_失败日志带成员component_id`（今天红：用的是 `slog.Default`）
  - `TestEnvelope_CloudEvents头往返且兼容旧X头`
  - `TestPump_空闲时轮询间隔退避到2秒`
- be-acceptance：`conformance/bus` 先对 jetstream 适配器跑；再写一个"故意丢 ack"的坏适配器，看它红。
- 项目：`make events-replay` 的集成测试：从 outbox 重放 8 天前的事件，消费者不重复处理。

### 6.6 foundations 文档大纲

**`06-event-bus.md`**

- **Scope**：broker 选型、送达语义、流与 durable、DLQ、回放、背压、客户端参数、Broker 端口。
- **Choice**：
  - JetStream；
  - 至少一次 + 游标做到 effectively-once；
  - outbox 是事实源；
  - pgqueue 是第二个适配器。
- **Port contract**：§6.4。
- **Alternatives**：§6.2 表。
- **Why / Why not**：表格各列。
- **When to switch**：
  - 客户已有 Kafka 并要求统一 → kafka 适配器；
  - 最小安装 → pgqueue；
  - 实测单流 > 5 万条/秒 → 分区。
- **How to switch**：改 `EVENT_BUS_URL`；跑一致性套件；用 outbox 重放补齐。
- **Conformance tests**：§6.4 列表。
- **Decision records**：修订 0106；新增"事件至少一次送达与建流方式"（events-consistency §6 第 1 步）。
- **Known limits**：`discard=old` 的取舍；不保证顺序。

**`07-event-contracts.md`**

- **Scope**：信封（CloudEvents）、命名（`<domain>.<aggregate>.<action>.v<n>`；历史上的 `sales.*` 保留，E10）、聚合类型与版本、状态 / 序列两种模式、schema 演进、载荷大小与 claim-check、事件里不放给人看的敏感字段（authz-architecture §4.7）。
- 其余小节同模板；Alternatives 写 Avro / Protobuf 事件 + 运行期 registry。

---

## 7. 议题五：缓存与 Redis（重审 0201）

### 7.1 逐项需求

| 需求 | 今天 | 推荐 | 要不要共享缓存 |
|---|---|---|---|
| 权限 bundle | 进程内，外壳里一份（`be-sdk-go/shell.go:273-276`） | 维持；ETag + poke（authz-architecture §4.3） | 不要 |
| JWKS | 进程内 | 维持；遇到没见过的 kid 时触发刷新（限频） | 不要 |
| 主数据快照 | PG 表 + 事件 | `Snapshot` 帮手（events-consistency §3） | 不要 |
| 授权投影 | 计划中的 `besdk_authz_acl` | 组件自己 schema 里的表 | 不要 |
| 展示用名称（BatchGet 结果） | BFF 每请求一个 DataLoader | 可选的进程内 LRU（TTL 30 s，事件触发失效） | 不要 |
| 限流 | 无 | 边缘层做（§8）；应用级配额用 PG 计数窗口 | 单机不要；多网关实例时限额按实例平摊 |
| 会话 | 无状态 JWT；refresh token 存 iam 的 PG | 维持 | 不要 |
| 幂等 | PG `command_idempotency` | 维持（E4 / E5） | 不要 |
| 分布式锁 | PG 行锁 / advisory 锁 | §3 的规范 + Jobs 租约 | 不要 |
| 第三方 token（钉钉 access_token） | PG 行 + 进程内互斥（`integration/im-dingtalk/backend/internal/tokenmgr/tokenmgr.go`） | 维持；跨副本刷新加一把事务级 advisory 锁 | 不要 |
| 热点读、报表 | 汇总表 | 维持（brickKit `09-patterns/01-component-design` 也建议报表走汇总表） | 不要 |

### 7.2 选项

| | 进程内 LRU | Valkey / Redis | PG unlogged 表 | PG 普通表 + LISTEN |
|---|---|---|---|---|
| 新增运维件 | 无 | 一个有状态服务 | 无 | 无 |
| 跨副本共享 | 否 | 是 | 是 | 是 |
| 失效 | 事件或 poke | TTL / pub-sub | TTL 清扫 | NOTIFY |
| 外壳 | 按成员实例化即安全 | 键要加成员前缀 | schema 隔离 | schema 隔离 |

### 7.3 推荐

- **0201 维持。** 措辞改成："没有缓存服务器；缓存只在进程内，通过 `besdk.NewCache[K,V](rt, name, maxEntries, ttl)` 创建。它有容量上限、TTL、singleflight、指标（`besdk_cache_hits_total{name}` 等），并能接 `Snapshot` 或事件做失效。"
- 外壳里每个成员一个实例，内存各自计算。门禁：模块代码里出现包级 `map` / `sync.Map` 当缓存时给警告。
- 端口形状（Get / Set / Delete / TTL）是所有缓存产品的公共子集，留着门，但**不建 Valkey 适配器**。重开条件沿用 0201 现有的"实测数据写下来，并且不止一个组件需要"，另外加一条："多副本部署下，进程内缓存的不一致窗口已经被业务判定不可接受。"

### 7.4 红测试

- `TestCache_超过容量按LRU淘汰`
- `TestCache_TTL到期后回源且并发只回源一次`
- `TestCache_事件失效后下一次读回源`
- `TestCache_外壳里两个成员同名缓存互不可见`
- 门禁 `module-global-cache-scan` 先对一个故意违规的样例跑红。

### 7.5 foundations 文档大纲：`11-caching.md`

- **Scope**：所有"把数据留在离用户更近的地方"的做法：缓存、快照、投影、汇总表。
- **Choice**：§7.3；§7.1 的总表就放在本节。
- **Port contract**：`besdk.Cache`。
- **Alternatives**：§7.2。
- **Why this choice**：单机资源有限；决策缓存最容易出错（撤销以后还在放行，authz-architecture §4.3）。
- **When to switch**：0201 的 Revisit 条件。
- **How to switch**：给 `Cache` 加 Valkey 适配器，键加成员前缀，配一个共享键 `CACHE_URL`。
- **Decision records**：0201（改写）、0202。
- **Known limits**：多副本时各副本的进程内缓存最多相差一个 TTL。

---

## 8. 议题六：边缘与网关

### 8.1 现状与证据

- Traefik v3.0：docker provider 加 file provider，后者的目录是空的（`infra/traefik/traefik.yml`；`infra/traefik/dynamic/` 下没有文件）。dashboard 是 `insecure: true`（注释写"仅开发"）。没有任何中间件（限流、请求体上限、CORS、ForwardAuth、超时、重试）。
- `edge_routes` 已在 10 个组件的 `assembly.yaml` 里声明（如 `erp/sales/assembly.yaml:6-7`：`{ path: /erp/sales/**, auth: required }`），但 be-ops 里没有任何读取它的代码（`tools/be-ops/internal/` 只有 `authzreg`、`dbscript`、`registry` 三个包）。
- 前端通过 `gatewayBaseUrl`（`components/frontend/standard/component.yaml:17`，默认 `/`）访问 `/api/...`。frontend 的 nginx 只发静态文件（`nginx.conf`），也就是说**浏览器到组件 REST 的路由今天没有任何生成物**。
- K8s：brickKit 只为 `expose: true` 的组件生成 Ingress，并要求写 `hostname`（`01-three-layers/03-deploy-yaml`）。没有看到"多个组件共用一个主机名、按路径前缀分流"的声明方式。
- 鉴权：在服务里（JWT 本地验签，0202 / 0203）。边缘什么都不做。
- request-id：SDK 在入站时生成（`gin.go:80-92`），出站不传；Traefik 不生成。

### 8.2 缺口

- E1 路由表没有生成物：边缘只能手写，而手写配置里带版本化的服务名，组件一发版就静默失效。brickKit `06-architecture/05-design-principles` 里专门拿"手写网关配置"当反例。
- E2 没有限流（0201 说归网关，网关却没有）。登录接口没有防爆破，只能靠 Casdoor。
- E3 没有请求体上限和边缘超时。
- E4 Docker 和 K8s 两种目标的边缘配置来源不统一。
- E5 内部头没有清洗：客户端可以伪造 `X-Request-Id`。今后如果 REST 上出现 `be-*` 之类的内部头，也必须在边缘剥掉。

### 8.3 选项

| | Traefik | nginx | Envoy Gateway | APISIX / Kong | Caddy |
|---|---|---|---|---|---|
| 单机资源 | 小 | 最小 | 中 | 中（需要 etcd / PG） | 小 |
| 动态配置 | docker / file / K8s provider | 要 reload | xDS / Gateway API | Admin API | API / 文件 |
| 限流 | 每实例内存令牌桶 | `limit_req`（每实例） | 本地 + 全局（要额外服务） | 插件，多种后端 | 插件 |
| K8s | IngressRoute / Gateway API | Ingress-NGINX | Gateway API 原生 | Ingress / CRD | 社区 |
| OTel | 内建 | 模块 | 内建 | 插件 | 内建 |

BFF 模式：每个渠道一个 BFF，还是前端直连。在服务里鉴权（零信任、纵深防御），还是在边缘集中鉴权。

### 8.4 推荐

1. **路由表由声明派生**：be-ops 读全部 `assembly.yaml` 的 `edge_routes` 加上 `brickkit.yaml` 的版本，输出 `build/edge/routes.json`（中立格式：路径前缀 → 组件 ID → 服务名:端口、`auth`、`body_limit`、`timeout`、`rate`）。再用生成器转成：
   - Docker：Traefik file provider（`infra/traefik/dynamic/routes.yml`）；
   - K8s：Ingress 规则或 Gateway API HTTPRoute（等 brickKit 支持按路径暴露，§12 F2；在那之前由 be-ops 产出一份清单，通过 `k8s.ingressAnnotations` 或独立 manifest 应用）。

   门禁：生成物和 `brickkit.yaml` 不一致时失败（同 `service-hostname-scan` 的思路）。
2. **边缘负责**：
   - TLS；
   - 按路径前缀路由；
   - 请求体上限（默认 10 MiB，上传走对象存储的预签名 URL）；
   - 边缘超时（responding / forwarding 的 header 超时 30 s）；
   - 粗粒度限流：每 IP 全局 100 r/s；`/api/iam/*` 每 IP 10 r/s、突发 20；
   - 生成 traceparent：Traefik OTel tracing 打开时，SDK 用 trace-id 当 request-id，响应带 `X-Request-Id`；
   - 剥掉客户端带来的内部头。
3. **边缘不负责**：鉴权、授权、数据范围、业务路由、重试 POST。JWT 永远在服务里验签：边缘被绕过，或者组件单独部署时，安全不能变弱（principle 1）。边缘可以选择预先验签来挡垃圾流量，但永远不能只靠它。
4. **BFF**：移动端保留 `infra/bff-mobile`；PC 直接调各组件 REST，需要的聚合由属主的 `batchGet` 解决，不加 PC BFF。BFF 永远不进外壳（0108）。
5. **CORS**：默认同源（前端和 API 用同一个主机名经过网关），不开 CORS。如果有独立来源（H5 子域、第三方），在边缘按白名单配置，组件里不写 CORS。
6. **应用级配额**（以后对外开放 API 时）：放在服务里，PG 计数窗口，挂在 API key 上，不上 Redis。

### 8.5 可替换性

Edge 端口 = 中立路由表 + 生成器适配器（traefik-file、k8s-ingress、gateway-api、nginx）。一致性测试：

- 黄金路由表：从一组 `assembly.yaml` 生成，与期望值比对；
- 端到端：`auth: required` 的路由不带 token 返回 401；未知路径 404；超过请求体上限 413；超过速率 429；响应带 `X-Request-Id`。

### 8.6 红测试

- be-ops：`TestEdgeRoutes_从assembly生成Traefik动态配置`（今天红：没有生成器）、`TestEdgeRoutes_组件升版后服务名随之变化`。
- 项目 e2e（`make verify` 扩展）：`登录接口每IP超限返回429`、`超过请求体上限返回413`、`客户端伪造的X-Request-Id不会进日志`。

### 8.7 foundations 文档大纲：`12-edge.md`

- **Scope**：浏览器和外部调用方到组件 REST 之间的一切。
- **Choice**：§8.4。
- **Port contract**：`routes.json` 的字段。
- **Alternatives**：§8.3 表，加上 BFF 的两种做法。
- **Why this choice**：派生胜过手写（brickKit 原则）；鉴权留在服务里保证单独部署时的安全。
- **When to switch**：
  - 多节点并且需要全局限流 → Envoy Gateway + 全局限流服务；
  - 对外开放 API → API key 与配额。
- **How to switch**：换生成器。
- **Decision records**：0106（网关不是组件）；新增"边缘只路由，鉴权在服务"。
- **Known limits**：限流按实例计。

---

## 9. 议题七：后台任务与调度

### 9.1 现状：全部后台循环

| 组件 | 循环 | 间隔 | 多副本安全 | 可观测 | 证据 |
|---|---|---|---|---|---|
| 12 个 Go 组件 | outbox pump | 200 ms | ✓（SKIP LOCKED） | 只有日志 | `be-sdk-go/outbox.go:34,58-84` |
| 12 份拷贝 | 周 / 月分区维护 | 24 h | ✗（先查后建，无 lock_timeout） | 只有日志 | `erp/inventory/backend/internal/partition/partition.go:25-110` 等 |
| 9 个组件 | 消费者 | — | ✗（核心订阅，每副本各收一份） | 只有日志 | events-consistency §2.1.1 |
| infra/workflow | 超期扫描 | 定时 | ✓ | 只有日志 | `module/module.go:64,106`；`repo/overdue.go:21-33` |
| infra/iam-casdoor | webhook 投递 | 循环 | ✓ | 只有日志 | `module/module.go:91`；`repo/webhookdeliveries.go:79-98` |
| integration/im-dingtalk | 发送结果回查 | 退避 | ✗（进程内 goroutine，重启就丢） | 无 | `consumer/consumer.go:121,192` |
| erp/sales | 补偿重试 | 请求里 sleep | ✗ | 无 | `tcc/confirm.go:172-215` |
| 计划中 | 预留清扫、sales 对账、`credit_check_pending`、快照回填、生命周期 / 冻结、ACL 拉取、游标与幂等键清理、`RunEvents` 维护 | — | — | — | 前四份 |

### 9.2 缺口

- J1 同一段循环代码抄了十几份（09 号约定"同一流程抄了几份，一份拿到了修复"）。
- J2 没有监督：
  - 外壳里 `Start` 失败就一直停着（`shell/run.go:164-181`），单跑时则是进程退出重启。行为不一致。
  - 组件 `Start` 在第一个循环退出时就返回，其余循环成了孤儿（`erp/finance/backend/module/module.go:54-66`）。
  - outbox pump 遇到 `context.DeadlineExceeded` 返回 nil（`outbox.go:77-79`）。如果这件事在 ctx 还没取消时发生，pump 就静默退出，单跑形态下进程也不会退。
- J3 单例任务（分区 DDL、生命周期）在多副本，以及"外壳和单跑同时在跑"（teardown 检查时）的情况下会并发执行。
- J4 没有"每个时间槽只跑一次"的 cron 语义：每天的提醒、Q4 开会计年度提醒（D7）都还没有地方放。
- J5 不可观测：看不到上次成功时间、耗时、失败数、队列深度。
- J6 没有事务内入队的作业队列（C3 的根因）。

### 9.3 选项

| | K8s CronJob | pg_cron | River（Go） | Graphile Worker / pg-boss（Node） | Temporal Schedules | APScheduler / Celery beat | 自研 SDK（PG 表） |
|---|---|---|---|---|---|---|---|
| 单机 Docker | brickKit 不生成 | 要装扩展、要超级用户，只能跑 SQL | ✓ | ✓ | 要集群 | Celery 要 broker | ✓ |
| 外壳与单跑一致 | 否（另起一个镜像，配置注入要重复一遍） | 否 | ✓ | — | — | — | ✓ |
| 事务内入队 | — | — | ✓（InsertTx） | ✓ | — | — | ✓ |
| Go 与 Python 对齐 | — | — | 只有 Go | 只有 Node | ✓ | 只有 Python | ✓（两份 SDK 用同一套表结构和语义） |
| 单例与按槽一次 | — | 有 | 领导选举 + periodic job | 有 | 有 | 要额外锁 | ✓ |

### 9.4 推荐：Jobs 端口

**声明方式**：模块在 `backend/module/jobs.go` 一个文件里列出全部任务（符合 09 号约定"一处登记"），`Start` 不再用来起循环。

```go
type JobKind int // Every | Singleton | Cron

type Job struct {
    Name     string        // 组件内唯一；指标、租约、日志都用它
    Kind     JobKind
    Interval time.Duration // Every / Singleton
    Cron     string        // Cron："0 3 * * *"；时区来自配置键 JOBS_TZ（默认 UTC）
    Timeout  time.Duration // 单次运行的截止时间
    Run      func(ctx context.Context) error
}

type Worker struct { // 消费 rt.Enqueue 入队的作业
    Kind        string
    Concurrency int
    MaxAttempts int
    Backoff     []time.Duration
    Run         func(ctx context.Context, j QueuedJob) error // 事务外；幂等靠 j.UniqueKey 或业务键
    OnDead      func(ctx context.Context, tx *sql.Tx, j QueuedJob) error // 重试用尽
}

type Module struct {
    HTTPHandler  http.Handler
    RegisterGRPC func(*grpc.Server)
    Events       EventsSpec           // events-consistency §2.4
    Jobs         []Job
    Workers      []Worker
    Reconcilers  []ReconcilerSpec     // §4.4
    Start, Stop  func(context.Context) error // 只做一次性初始化；门禁警告模块代码里的 time.NewTicker
}

func (rt *Runtime) Enqueue(ctx context.Context, tx *sql.Tx, kind string, args any, opt EnqueueOptions) error // opt: RunAt, UniqueKey
```

**四种语义**

| 类型 | 语义 | 实现 | 典型用户 |
|---|---|---|---|
| `Every` | 每个副本都跑，靠 SKIP LOCKED 认领工作，天然竞争 | 定时器 | outbox pump、清扫 |
| `Singleton` | 全局同一时间只有一个在跑 | 租约表 `besdk_job_lease(name PK, holder, epoch, expires_at)`：`UPDATE … WHERE expires_at < now() RETURNING epoch`；每过 TTL/3 续约一次；丢了租约就取消这次运行的 ctx；epoch 作为防护令牌 | 分区 DDL、生命周期冻结、快照回填 |
| `Cron` | 每个时间槽全局只跑一次 | `besdk_job_slot(name, slot_at, holder, done_at, PRIMARY KEY(name, slot_at))`：`INSERT … ON CONFLICT DO NOTHING` 抢槽，**不需要领导者**；错过的槽默认只补跑最近一个 | 日报、年度提醒 |
| `Queue` | 在业务事务里入队，至少执行一次 | `besdk_job_queue`（id、kind、args jsonb、unique_key、run_at、attempts、state、lease_until、last_error）；认领用 SKIP LOCKED；完成的行按保留期清理（不分区，同 E12 的例外） | 异步命令（§4.4 L2）、开异常待办、钉钉回查 |

**监督**：

- 每个任务一个 goroutine，带 recover。出错或 panic 时，用成员的 logger 记一条，加指标，按退避（1 s → 5 min）重启。
- 外壳和单跑用同一段监督代码，行为一致（修 J2）。
- 任一任务退出不影响其他任务。

**可观测**：

- 指标：`besdk_job_runs_total{job,result}`、`besdk_job_duration_seconds{job}`、`besdk_job_last_success_timestamp_seconds{job}`、`besdk_queue_depth{kind,state}`、`besdk_queue_oldest_age_seconds{kind}`。
- 附带告警规则模板，例如"某 Singleton 超过 3 个周期没有成功"。
- 可选的只读运维端点 `/{domain}/{name}/_ops/jobs`，权限键 `<domain>.<name>.ops` 由 be-ops 自动登记。

**表的位置**：都在组件自己的 schema 里，由 SDK 的迁移步骤创建（同 data-layer 的平台表）。外壳和单跑同时运行时，用的是同一个 schema 里的租约和槽，天然互相协调（修 J3）。

**Python**：同一套表结构和语义，用 asyncio 任务实现；一致性套件的语义向量两边共用。

**分区维护、生命周期、`RunEvents` 的维护循环**都改成 `Singleton` / `Every` 的登记项，12 份 `partition` 包退役。

### 9.5 可替换性

Jobs 是一个端口，但现实中只有一个适配器（原生 PG 表）：

- River 只有 Go，破坏 Go 与 Python 的语义对齐，只作参考实现；
- Temporal Schedules 要等引擎（§4.5）。

所以文档里**如实写"单适配器端口"**。端口的价值在于语义统一和一致性测试，不在于能换。将来 DBOS 如果被采用，可以作为 `Queue` 的第二实现。

### 9.6 红测试

- be-sdk-go：
  - `TestJobs_两个副本同一Cron槽只跑一次`
  - `TestJobs_Singleton两个副本同时只有一个在跑`
  - `TestJobs_Singleton丢失租约后取消当次运行`
  - `TestJobs_任务panic后按退避重启并计数`
  - `TestJobs_一个任务退出不影响其他任务`
  - `TestQueue_业务事务回滚则作业不存在`
  - `TestQueue_重试用尽调用OnDead`
  - `TestQueue_两个副本每个作业只执行一次`
- 外壳：`TestShell_成员后台任务失败后被重启而不是永久停止`（今天红）。
- 组件（迁移前跑红）：
  - finance：`TestModuleStart_一个循环退出时其余循环被取消`；
  - inventory：`TestPartition_两个副本并发维护分区不报错`、`TestPartitionDDL_被长事务阻塞时在lock_timeout内放弃且不堵写入`。
- 门禁：`module-ticker-scan`（模块代码里出现 `time.NewTicker` / `asyncio.sleep` 循环就警告）。

### 9.7 foundations 文档大纲：`13-background-jobs.md`

- **Scope**：组件内所有不由请求触发的工作。
- **Choice**：
  - Jobs 端口；
  - 四种语义；
  - 声明式登记；
  - SDK 监督；
  - 表放在组件自己的 schema；
  - 不用 K8s CronJob，不用 pg_cron。
- **Port contract**：§9.4 的 API 与表结构。
- **Alternatives**：§9.3 表。
- **Why this choice**：外壳和单跑一致；Go 与 Python 对齐；事务内入队。
- **Why not the others**：表格各列。
- **When to switch**：作业量超过 PG 能承受的写放大（实测每秒上千个作业）→ 作业改走 bus；需要流程引擎时见 05。
- **Conformance tests**：§9.6。
- **Decision records**：新增"后台工作只经 SDK 的 Jobs"。
- **Known limits**：单适配器；Cron 精度到秒级。

---

## 10. 议题八：外壳合并安全逐项核对

| 项 | 外壳里的风险 | 设计如何保证合并安全 | 验证 |
|---|---|---|---|
| 事务身份 | 无 LOCAL 的 SET 泄漏 | SET LOCAL（已有）；Store 绑定成员身份（data-layer D1） | 已有测试 + `conformance/store` |
| 事务超时 | 成员角色的 `ALTER ROLE SET` 不生效（T7） | SDK 每个事务 SET LOCAL | `TestTx_外壳登录角色…`（固定事实） |
| 连接池 | 一个无上限的共享池（`shell/run.go:113`）；Python 池共 10 条 | 外壳池大小 = Σ 成员预算（有上限）+ 每成员信号量 | `TestPool_…预算耗尽不影响另一个成员` |
| advisory 锁 | 同名键在成员之间相撞；会话级锁泄漏 | 键 = (hash(成员 ID), hash(name))；只用事务级 | `TestLockKey_…互不阻塞` |
| 事务内网络守卫 | — | ctx 标记按调用链传递，与进程无关 | `TestTx_事务内发起gRPC…` |
| gRPC 客户端 | 进程级连接池会让 `be-caller` 变成别的成员 | 连接池挂在成员的 rt 上 | `TestConn_外壳里be_caller是发起成员` |
| gRPC 服务端 | — | 每个成员自己的 `grpc.Server`、自己的拦截器链（已有 `ServeExtraPort`） | 已有 |
| HTTP 服务端 | 零超时 | `serveHTTP` 统一设 ReadHeader / Read / Write / Idle 超时（外壳和单跑共用） | `TestHTTPServer_…` |
| 截止时间与重试预算 | 共享的 throttling 会让一个成员的风暴耗尽别人的预算 | service config 的 throttling 是按 ClientConn 计的，连接按成员分开，所以预算也按成员分开 | `conformance/rpc` |
| NATS 连接 | 外壳共享一条连接；断线后全体失联 | 一条连接 + 永久重连；每个成员的 durable / 订阅名带成员 ID（events-consistency §2.2.4） | `TestNATS_…`、`TestConsume_外壳里两个成员…` |
| outbox pump | N 个成员 × 每秒 5 次空转 | 自适应轮询 | `TestPump_空闲时…` |
| 事件游标、幂等表 | — | 表在成员自己的 schema | 已定 |
| Jobs 租约与槽 | 单跑和外壳同时在跑时重复执行 | 表在成员 schema，跨进程互相协调 | `TestJobs_…` |
| 后台任务失败 | 外壳里永久停止，单跑时退出重启 | SDK 监督，两种形态行为一致 | `TestShell_成员后台任务失败后被重启…` |
| 缓存 | 包级 map 在成员之间共享 | `besdk.Cache` 按成员实例化 + 门禁 | `TestCache_外壳里…` |
| trace | `service.name` 全是外壳名（`InitOTel(cfg.ShellName)`，`shell/run.go:104`） | 每个成员一个 TracerProvider（resource 的 `service.name` = 成员 ID），共用一个导出器；传播器在 Bootstrap 里设一次 | `TestShell_每个成员span的service.name是成员ID`（今天红） |
| 日志 | SDK 内部用 `slog.Default()`（`events.go:69`） | SDK 内部一律用 `rt.Logger` | `TestConsume_失败日志带成员component_id` |
| 指标 | — | 每成员一个 Registry（已有） | 已有 |
| 授权 bundle / JWKS | — | 进程级一份（已有 `InitShellAuthz`）；ACL 投影每成员一份（authz-architecture §4.5） | 已有 |
| 边缘路由 | 指向外壳服务名，外壳一升版就失效 | 路由表用**成员自己的服务名**（brickKit 会把它做成外壳容器的网络别名 / K8s Service），和 0107 是同一条规则 | `TestEdgeRoutes_…` |
| 爆炸半径 | 外壳重启 = N 个成员同时不可用 | JetStream durable 保留进度；Reconciler 推进进行中的流程；重试预算吸收抖动 | 外壳组装后的 T22 真机测试 |

外壳不变量（写进 `18-shells.md`）：

1. 外壳里每个"进程级"的东西只有四样：OTel 导出器 + 传播器、授权 bundle / JWKS、DB 池、NATS 连接；
2. 其余一切按成员实例化；
3. 每个成员有自己的资源预算（DB 连接、出站并发、缓存内存）；
4. 后台任务的监督在两种形态下行为相同。

---

## 11. (a) foundations 文档目录

### 11.1 位置与编号

`docs/en/04-foundations/` 和 `docs/zh/04-foundations/`，文件一一镜像（`make docs-mirror` 自动覆盖）。根 `AGENTS.md` 里写的"运维文档将放在 `docs/en/04-operations/`"顺延为 `05-operations/`（那个目录还不存在，改一行就行）。`docs/en/README.md` 的内容表加一行。

阅读顺序：

- 写组件的人：读 01 约定，必要时读 02 决策；
- 改 SDK、改基础设施、或想提议"换 X"的人：先读 04。

### 11.2 文件清单（每份对应一个关键选择）

| 文件 | 一句话范围 |
|---|---|
| `README.md` | 索引；§2.2 的端口登记表（端口、默认适配器、备选、一致性套件、状态）；每份文档的 11 个固定小节 |
| `01-ports-and-adapters.md` | 端口的判据、适配器怎么选（URL scheme）、一致性测试怎么组织、SDK 版本策略、"单适配器端口"如何如实标注 |
| `02-database.md` | 数据库选型：PG 方言族、版本承诺（≥ 14，NOINHERIT 要 16）、兼容发行版（待实测）、pgdialect 层、`Store` 与库身份、连接池与 pgbouncer |
| `03-data-lifecycle.md` | 冷热：在线即挂载、冻结到对象存储、分区窗口由 SDK 维护、保留期默认值、无界表的例外（来自 data-layer） |
| `04-local-transactions.md` | 本地事务（§3.7 的大纲） |
| `05-consistency-across-components.md` | 跨组件一致性（§4.8） |
| `06-event-bus.md` | 队列选型与 Broker 端口（§6.6） |
| `07-event-contracts.md` | 事件信封、命名、聚合流、schema 演进（§6.6） |
| `08-system-rpc.md` | gRPC 系统面（§5.8） |
| `09-user-api.md` | REST 用户面与错误模型（§5.8） |
| `10-deadlines-and-retries.md` | 时间预算、重试预算、舱壁（§5.8） |
| `11-caching.md` | 缓存与 Redis（§7.5） |
| `12-edge.md` | 边缘与网关（§8.7） |
| `13-background-jobs.md` | 后台任务（§9.7） |
| `14-authorization-provider.md` | 授权 provider 契约、资源契约、槽位族与 authzconf（来自 authz-architecture） |
| `15-identity-provider.md` | IAM 槽位、token 形状、JWKS、gRPC 上的服务身份扩展点（来自 identity-permissions） |
| `16-object-storage.md` | S3 API 端口、冻结存储接口、claim-check |
| `17-observability.md` | OTel 传播（traceparent、request-id = trace-id）、RED 指标、日志字段、外壳里的成员身份 |
| `18-shells.md` | 合并安全：§10 的逐项表和四条外壳不变量 |

### 11.3 与 `02-decisions/` 和 `01-conventions/` 的分工（不重复）

| 层 | 写什么 | 不写什么 |
|---|---|---|
| `02-decisions/`（ADR） | 结论一句、两三句理由、Rules out 列表、Revisit 条件；**末尾一行"完整分析：`../../04-foundations/<file>.md#<section>`"** | 方案对照、端口契约、测试清单 |
| `04-foundations/` | 我们的选择、端口契约、备选对照、为什么选它、为什么不选别的、什么时候换、怎么换、一致性测试；`## Decision records` 小节列出它支撑的决策编号并链过去 | 不复述 Rules out（链到决策）；不写"怎么用 API"的编码规则（链到约定） |
| `01-conventions/` | 怎么用：API、写法、易错点 | 为什么这样选（链到 foundations） |

**每份 foundations 文档固定的 11 个 `##` 小节**（两种语言节数相同，方便 docs-mirror 校验，也方便 AI 定位）：

1. Scope
2. Choice
3. Port contract
4. Alternatives
5. Why this choice
6. Why not the others
7. When to switch
8. How to switch
9. Conformance tests
10. Decision records
11. Known limits

可选新门禁 `make docs-foundations`：

- 每份 foundations 文档的 Decision records 里至少有一条有效链接；
- 被链到的决策文件末尾，要有一条回链到这份 foundations 文档。

**新增或改写的决策**：建议新开文件夹 `05-runtime/`（0501–0599），收运行期机制：

- 0501 事务内不走网络；
- 0502 隔离级别与重试策略；
- 0503 截止时间与重试预算；
- 0504 错误模型与 reason 登记表；
- 0505 事件信封（CloudEvents）与聚合流游标；
- 0506 事件至少一次送达与建流方式（承接 events-consistency）；
- 0507 后台工作只经 SDK 的 Jobs；
- 0508 边缘只路由，鉴权在服务；
- 0509 SDK 基础端口与一致性测试（也可以放进 01-architecture 作为 0109）。

改写的：

- 0106：事件总线可以通过 SDK 适配器 + URL scheme 更换，但不是一个开关；
- 0201：没有缓存服务器，缓存经 `besdk.Cache`；
- 0103：BFF 用 Yoga。

0208（gRPC 系统面）和 0304（BatchGet 上限）按前文的提议放在原来的文件夹。

---

## 12. (b) brickKit 反馈候选

> 按记忆里的规则"给 brickKit 的反馈只放重建后验证过的"：下面全部是**候选**，没有在 brickKit 上复现验证过，应该先进 `dev/phase-06/to-verify.md`，验证后再写反馈。判断依据只来自 `brickkit docs`（v1.1.0），没读源码，所以"brickKit 不支持"的说法要以验证结果为准。

| # | 候选 | 依据 | 对 AI 开发者的帮助 |
|---|---|---|---|
| F1 | `extraPorts[]` 增加 `protocol: grpc | http | tcp`；K8s 上据此生成 `appProtocol`，并可选生成一个 headless 的伴生 Service（`<svc>-headless`），供客户端负载均衡 | schema 里 extraPorts 只有 `name` / `port`（`11-reference/01-component-yaml-schema` 第 92-93 行）；gRPC 长连接在 ClusterIP 上会被 L4 钉死 | AI 不用知道"kube-proxy 是 L4"这种隐性知识，声明协议就够了 |
| F2 | 由组件声明派生边缘路由：`expose.paths`（多个组件共用一个 hostname，按路径前缀分流），K8s 生成 Ingress 规则或 Gateway API HTTPRoute，Docker 生成 Traefik label 或 file 配置 | 今天 `expose` 一个组件一个主机名；`05-design-principles` 自己把"手写网关配置会随版本静默失效"当成反例 | 消除最典型的"第二份手抄配置" |
| F3 | `09-patterns/04-service-calling` 补一节 gRPC：连接复用、按端口名取地址并去掉 `http://`、截止时间、keepalive / MaxConnectionAge、只对幂等方法重试；并指出"每次现拨"会掩盖 L4 负载均衡问题 | 现在那页只有 HTTP 客户端的实验 | 本项目踩过的坑可以直接写成通用指引 |
| F4 | 区分 readiness 与 liveness：component.yaml 可选 `readinessCheck`（K8s 生成 readinessProbe；compose 忽略或映射到 depends_on 条件） | schema 里只看到 `healthCheck`（`startPeriodSeconds` 等，第 117 行）；本项目"bundle 没拉到之前答 503、/healthz 照样绿"的语义，在滚动更新时会把流量导给还没就绪的 Pod | AI 不必在"健康检查不许查依赖"和"别把流量给未就绪实例"之间二选一 |
| F5 | 优雅停机时长：`deployment.stopGracePeriodSeconds`（compose `stop_grace_period`，K8s `terminationGracePeriodSeconds`） | 文档里没有看到这个字段；JetStream 在途的 ack、outbox 批次需要几秒收尾 | — |
| F6 | 外壳文档补"成员身份不变量"：telemetry 的 `service.name` 应当是成员 ID（每成员一个 provider）；每成员资源预算（连接、并发）；PG 的 `ALTER ROLE SET` 在 `SET ROLE` 之后不生效 | `04-shell/*` 讲了配置注入和端口，没讲进程内资源的归属 | 写外壳的 AI 最容易犯的是"最后一个初始化的赢"这类错误 |
| F7 | 可选的事件声明：`events.publishes / subscribes`，只用于 `brickkit graph` / `status` 展示异步边，以及 lint 警告"订阅了一个项目里没人发布的 subject" | brickKit 的图里只有同步依赖边；异步拓扑对 AI 不可见 | AI 判断"改这个事件会影响谁"时不用全仓 grep |
| F8 | 文档化"槽位族契约仓库 + 一致性测试套件"模式（比如 `contract-<family>` 仓库、族成员在 CI 里跑同一个套件） | `09-patterns/01-component-design` 讲了族的四条规则，没讲怎么证明成员可替换 | 给 AI 一个可照做的"可替换"验收方式 |
| F9 | 后台任务与副本的模式页：单例 / 按槽一次 / 竞争认领，以及"外壳和单跑同时在跑"时的重复执行 | 平台不管运行期，但这是每个用 `replicas` 或外壳的项目都会遇到的问题 | — |

---

## 13. (c) 要用户拍板的点（只列业务或方向性问题）

| # | 问题 | 推荐 | 影响 |
|---|---|---|---|
| ★Q1 | 部署承诺：一期只承诺单机，还是同时承诺 K8s 多副本？ | 一期单机为主，K8s 多副本"可用但不调优"；设计按多副本正确来写（租约、按槽一次、MaxConnectionAge） | 决定 F1 / headless 和全局限流要不要现在做 |
| ★Q2 | 事件总线要不要现在就建第二个适配器（PG 队列）来证明可换？ | 建（同 A6 对 authz 的判断：第二个真实实现越早，越能逼出契约偏差）；Kafka 等客户提出再建 | 多一份 SDK 工作量和一致性套件 |
| ★Q3 | 是否预期会出现跨天、多人、多组件的长流程（采购到付款、项目结算），并且需要"按单看流程历史"？ | 现在不建引擎；第一个这样的流程出现时评估 DBOS | §4.5 的切换条件 |
| ★Q4 | 对外开放 API（客户的其他系统、第三方）在不在路线图上？ | 在的话，09-user-api 加 API key、配额、版本承诺；边缘加按 key 限流 | 影响 Connect 的重议与配额设计 |
| ★Q5 | 财务凭证号必须连续无缺口吗？ | 按国内实务"凭证号按期连续"，维持今天每个法人串行过账的做法（吞吐约每秒几十到上百张），写明上限 | 不要求的话，可以改成 sequence，并发更高 |
| ★Q6 | 用户操作最长愿意等多久？ | 普通操作 10 s；确认订单这类编排 15 s；导出走异步 | 截止时间预算的默认值 |
| Q7 | 跨组件视图出现"几秒后才看到"（确认订单 → 应收台账）能不能接受，前端显示"同步中"？ | 接受 | §4.6 |
| Q8 | 文档结构：新建 `docs/*/04-foundations/`（18 份），运维顺延到 05；新开决策文件夹 `05-runtime/` | 同意 | 08-documentation 约定"拆分、重组要先征得人同意"，所以需要你点头 |
| Q9 | `resources.tsv` 里的 kafka、rabbitmq 替换件：删除，还是保留并标"无 SDK 适配器"？ | 删 rabbitmq；kafka 保留并标"适配器待建" | 避免兑现不了的承诺 |

---

## 14. 落地顺序（与前四份合并）

贴合 events-consistency §6 和 data-layer §6：同一轮 be-sdk v0.6.0 加组件发版。

1. **P0：外壳 T21–T24 之前，随 v0.6.0**
   - 三种超时 + 重试 + 网络守卫 + 嵌套守卫（§3）；
   - 池上限与每成员信号量；
   - NATS 客户端参数；
   - gRPC 连接复用 + keepalive + 默认截止时间 + otel 传播；
   - HTTP 服务端超时；
   - 游标键改为聚合流；
   - CloudEvents 头名；
   - 每成员一个 TracerProvider；
   - 去掉 `slog.Default()`；
   - inventory 按顺序加锁；
   - sales `credit.rejected` 不再持锁调用；
   - iam / BFF 补上截止时间。

   理由：这些会改到外壳的 `go.mod` 和运行期行为，晚做就要重组一次外壳。
2. **P1：v0.6.x，与 06c 同步**
   - Jobs / Reconciler / Enqueue（替换 12 份 partition、sales 的 sleep 补偿、im-dingtalk 的 goroutine）；
   - 错误模型与 reason 登记表（前端 06c 会用到）；
   - 重试策略从 `idempotency_level` 生成，加门禁；
   - be-ops 的边缘路由生成器。
3. **P2**：Broker 端口 + pgqueue 适配器 + `conformance/bus`；`make events-replay`；`besdk.Cache`；`conformance/{store,rpc,jobs}`。
4. **P3：按触发条件**：kafka 适配器、headless 负载均衡（等 F1）、引擎评估（Q3）、对外 API（Q4）。
5. **文档**：§11 的目录，先写 README、01、04、05、06、08、10、13、18（P0 和 P1 用得到的），其余跟着 P2 补；每份中英镜像。
6. **和 `sdk-redesign.md` 的接口**：`Module` 的新字段（Events / Jobs / Workers / Reconcilers）、`rt.Store` / `rt.Conn` / `rt.UserHTTP` / `rt.Enqueue`、`TxOptions`、Bus 端口的内部包边界、Python 的同形 API，都交给 sdk-redesign 统一定名，并列出三个语言的迁移路径。
