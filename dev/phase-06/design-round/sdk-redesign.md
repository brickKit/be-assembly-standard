# SDK 重新设计：组件协议、黑盒一致性测试、三门官方 SDK 与迁移路径

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮，lane A）。只读调研，未改任何代码、未提交。
> 输入：同目录七份分析（`events-consistency`、`data-layer`、`identity-permissions`、`authz-architecture`、`data-lifecycle-v2`、`foundations-communication`、`foundations-data-platform`）、`../dept-scope-analysis.md`、`decisions.md`，以及**优先于一切分析的** `answers.md`；裁决 R38–R63（`.superpowers/sdd/plan-06b/takeover.md`、`progress.md`）。
> SDK 现状来自 be-sdk-go / be-sdk-python / be-sdk-ts 三个仓库 v0.5.0 的代码（行号以写作时工作区为准），外壳来自 `shell/be/*`，门禁来自 `tools/be-acceptance`，生成器来自 `tools/be-ops` v0.2.0。brickKit 只读了本机 v1.1.0 文档（`brickkit docs`）和源码仓库 `docs/en/`。
> 姊妹文件 `sdk-redesign-apis.md`：三门语言逐个 API、外壳启动器、夹具组件、第四门语言指南。本文件：结论、协议、一致性套件、现状盘点、迁移路径、brickKit 候选。

---

## 0. 结论（一页）

1. **用户唯一的要求（L1）：每个组件可以自由选语言。** 于是"规则"不能再住在某一门语言的 SDK 里。本设计把规则抽出来，叫 **组件协议 `be-protocol` 1.0**：在线协议、表结构、配置键这一层，定义一个组件要成为本项目合格成员必须做到的一切（§2，二十章）。三门 SDK 降为这份协议的**官方参考实现**。
2. **三样东西，各有一个家。**
   - **协议**：新仓库 `brickKit/be-protocol`。里面只有规范正文（英文为准、中文镜像）、JSON Schema、平台表参考 DDL、语义向量、夹具组件契约，**没有代码**。按 `MAJOR.MINOR` 版本化，minor 只增可选面（§3）。新建仓库要用户同意（§9 Q1）。
   - **黑盒一致性套件 `compconf`**：放在 `tools/be-acceptance/conformance/component/`（compconf 只作它的非正式简称）。对一个**运行中的容器**测，不看语言。套件自带假 IdP、假 authz、假对端和 OTLP 接收器，用真 PG 和真 JetStream。共 15 个 profile，按组件清单自动选用；结果写成测试记录。`make gates` 只校验"这个组件当前版本 + 镜像摘要有一份全绿记录"（§4）。
   - **三门官方 SDK**：API 同形（§5，细节见 apis 文件）。每门 SDK 自带同一个夹具组件 `widget`（契约在 be-protocol 里），CI 对它跑 compconf。三门 SDK 能做同样的事，靠的就是"同一个 widget 在三门语言里都过同一套黑盒"。**TS 补齐数据库、迁移、事件、幂等和 Jobs**，栈锁定为 Node 24 + Fastify 5 + grpc-js + node-postgres + node-pg-migrate（§5.3）。
3. **准入规则**：0105 重写，0103 重新解释（§7.6）。
   - 任何语言的组件，只要过了 compconf，就能进项目**单独运行**。
   - 要**进外壳**，这门语言得先有官方 SDK 和外壳启动器。外壳是一个进程，只能装同一门语言、同一个 SDK 版本的成员。
   - 一门语言出现第二个组件之前，必须先锁定一套栈（0103 加一行）。
   - JVM / CLR 的内存和冷启动成本，写进该组件 BRICKKIT 的"Before you deploy"，作为文档提醒，不再是禁令。
4. **统一命名**（三门语言同一套名词，§5.2）：
   - 入口与模块：`Spec` + `Main`；`Module{HTTP, GRPC, Events, Jobs, Workers, Reconcilers, Snapshots, Sharing, Lifecycle, Start, Stop}`。
   - 数据库：`rt.Store()` 绑定库身份；`Store.Tx(ctx, fn)` / `TxWith(ctx, TxOptions, fn)` / `ReadSnapshot`。
   - 事务里的动作：`tx.Publish`、`tx.Enqueue`、`tx.Lock`、`tx.NextNumber`、`tx.SyncRelation`。
   - 调别人：`rt.Conn(dep, port)` 走系统面，取代 `SystemClient` / `UserClient`；`rt.UserHTTP(dep)` 走用户面；`rt.ExternalHTTP(name)` 调第三方。
   - 授权：`AccessFrom(ctx)` 一个入口，取代 `ScopeOf` / `UserFrom` / `ScopeFrom`。
   - 帮手与测试：`NewSnapshot[T]`、`NewReconciler[T]`、`NewCache[K,V]`、`besdktest`。
5. **四个形状定死**：
   - SDK 拥有的表一律带 `besdk_` 前缀，参考 DDL 见附录 A。
   - 事件游标按 `(consumer, aggregate_type, aggregate_id)` 建键。
   - 信封用 CloudEvents 1.0 二进制模式。
   - 错误体是 RFC 9457 problem+json，里面装的是 AIP-193 的 `reason` / `domain` / `metadata`；协议指标一律 `be_` 前缀。
6. **版本**：
   - 协议 1.0；三门 SDK 都是 **v0.6.0**，实现协议 1.0。pilot（§7.2 阶段 C）之后冻结 API，此后只增。T25 外壳真机验证通过后，同一份代码原样打 **v1.0.0**。
   - 13 个组件一次升 **3.0.0**（F3：UUIDv7，重建迁移基线），Go 模块路径改成 `/v3`；外壳升 1.1.0。
   - **不做任何兼容层**：events-consistency 的 `Consume` 兼容层、identity 的 `ScopeOf` 弃用包装、data-layer 的 `WithTx` 过渡包装、authz 的 v1 bundle 退化，全部取消。理由有三：一次迁完；没有生产数据；外壳今天没有任何成员（`members: []`）。
7. **现状核实**：三门 SDK 和外壳里一共核实了 45 条问题，每一条都对到一条协议条款和一处 SDK 改动（§6.2）。最危险的几条：
   - 没有任何超时；
   - 池没有上限，且外壳成员共用一个；
   - gRPC 每次调用都现拨一条连接；
   - NATS 断线约两分钟后永久失联；
   - 刷新令牌能当访问令牌用，Python 还会拒收所有带 `aud` 的令牌；
   - 单跑时 `Start` 出错，进程以 0 退出；
   - Python 的 outbox 用裸 `SELECT` 认领，消费是桩代码。
8. **迁移**：五个阶段，lane 可以并行（§7.7）。必须在外壳 T21–T24 之前完成的清单见 §7.8。
9. **要用户拍板的 3 点**（§9；Q1、Q3 已由用户答复为 P1、P2，Q2 按推荐采纳为 P3）：
   - 新建 `be-protocol` 仓库（已答复 P1：建）；
   - "同一门语言第二个组件前锁栈"这条准入规则；
   - `mdm/org`（法人日历）和 `mdm/currency`（汇率）放不放进这一轮。已答复 P2：这一轮就建，排在其余组件升 3.0.0 之前；不留 `LEGAL_ENTITIES` 过渡变量，汇率不限定为 1。

---

## 1. 范围，以及本文对前文的裁决

本文是设计轮最后一份，统一给前七份留给 `sdk-redesign.md` 的名字、位置和版本下结论。下表列出本文改了前文结论的地方；表里没出现的，原样采用。

| # | 前文 | 前文结论 | 本文裁决 | 理由 |
|---|---|---|---|---|
| 1 | events-consistency §2.4 | v0.6.0 带兼容层：`Consume` / `StartOutboxPump` 旧签名跑在 JetStream 上，用 advisory 锁修分区 inbox | **不做兼容层**，旧 API 直接删 | F3 定为 3.0.0 一次迁完、重建基线；外壳今天没有成员，不存在"外壳把没改代码的 2.0.x 成员抬到新 SDK"这种情况 |
| 2 | events-consistency §2.5 / §6、data-layer §6 | 组件发 2.1.0 / 2.0.x | **全部 3.0.0** | F3 |
| 3 | events-consistency §1.2 | 游标主键 `(subject, aggregate_id)` | `(consumer, aggregate_type, aggregate_id)` | 主键去掉 subject，按聚合建键，见 foundations-communication §4.2 C1。另加 `consumer` 列（投影名）：同一组件里两个互相独立的投影可以各有各的游标，默认是 `''` |
| 4 | events-consistency §1.1 | `X-` 头 | CloudEvents 二进制模式头，**不再读旧 `X-` 头** | 同第 1 条：新旧版本不会同时在线 |
| 5 | events-consistency §2.2.3 | `hop_count > 5` 进 DLQ | 上限改为 **10**，是协议常量 | 合法链路已经接近 5 跳：订单 → finance → `credit.rejected` → sales → 待办事件 → notification → IM 结果。防环只为拦住无限循环 |
| 6 | 各文 | `event_outbox`、`event_cursor`、`command_idempotency`、`snapshot_sync` | 改名为 `besdk_outbox`、`besdk_event_cursor`、`besdk_idempotency`、`besdk_snapshot_sync` | 基线要重建，正好统一前缀。门禁于是只需一条规则："组件 SQL 不许碰 `besdk_*`" |
| 7 | 各文 | 指标前缀 `besdk_` | 前缀 **`be_`** | 这是协议指标，第四门语言的组件也要发，不该带 SDK 的名字 |
| 8 | data-layer §2.5 | `Store.Tx(ctx, fn func(*sql.Tx))`，`TxOptions` 只有 ReadOnly / LockTimeout | 用 foundations-communication §3.4 的形状：`fn(ctx, tx)`，`TxOptions` 带隔离级别、三种超时和重试次数；tx 是 SDK 自己的 `*besdk.Tx` 类型 | `ctx` 要带"在事务里"的标记；`tx` 要能直接 `Publish` / `Enqueue` |
| 9 | data-layer §2.5 | `WithTx` 保留一个 minor | 删除 | 同第 1 条 |
| 10 | data-layer §3.4、data-lifecycle-v2 §0 | 生命周期任务每个 schema 一把 advisory 锁 | 引擎作为 `Jobs.Singleton` 运行（租约可观测）。每一步内部**另外**再取事务级 advisory 锁，键由 schema 派生 | 单跑和外壳同时在跑、多副本，这几种情况都靠租约 + 步骤锁两层保护 |
| 11 | data-layer D6 | `ClaimBatch` | 并入 `Jobs.Queue` / `Reconciler` | foundations-communication §0.4 已指出这两个名字说的是同一件事 |
| 12 | identity-permissions §6.3 | `UserFrom` / `RequireUser` / `ScopeFrom` / `HasPermission`，`ScopeOf` 保留一版 | 统一成 authz-architecture §4.1 的 `AccessFrom(ctx)`：用户是 `a.User()`，功能键是 `a.Has(k)`，范围是 `a.Scope(type)`。`ScopeOf` 直接删 | 一个入口；同第 1 条 |
| 13 | identity-permissions §5.3 | `Dial(ctx, cfg, dep, extra)` 每次返回新连接 | `rt.Conn(dep, port)` 按成员缓存；`be-actor-sub` 每次调用时从 ctx 取 | foundations-communication §0.4 |
| 14 | identity-permissions §5.3、events-consistency §1.3 | 幂等的 caller 取 `user:<sub>` / `system` | 取 `user:<sub>`、`svc:<be-caller>`、`system`（只有本组件自己的后台任务用）。系统面请求**必须**带 `be-caller`，否则答 `UNAUTHENTICATED` + `MISSING_CALLER` | 有了服务身份，命名空间可以更细；审计也可靠 |
| 15 | authz-architecture §3.10 | 新 SDK 能退化读 v1 bundle | 不支持 v1；协议 1.0 要求 `contract: authz/2.x` | authz 和其它组件同一批升 3.0.0 |
| 16 | authz-architecture §5.1 | `AUTHZ_BUNDLE_URL` 保留一版，由 `AUTHZ_URL` 派生 | 只有 `AUTHZ_URL` | 同上 |
| 17 | authz-architecture §5.4、foundations-communication §2.3 | 套件位置分别是 `be-acceptance/authzconf/`、`be-acceptance/conformance/<port>/` | 统一为 `tools/be-acceptance/conformance/<端口短名>/`（组件协议套件是 `component/`；`compconf`、`authzconf` 只作非正式简称）；**语义向量不放在任何套件里，搬进 be-protocol 的 `vectors/`** | 规范和向量必须同一个版本号；三门 SDK 从 be-protocol 的 tag 同步向量 |
| 18 | data-lifecycle-v2 §4.14 | Go 路径 `be-sdk-go/v1/lifecycle` | `github.com/brickKit/be-sdk-go/lifecycle` | Go 的 v0 和 v1 都不带主版本后缀 |
| 19 | events-consistency、identity、data-layer | TS "不加"：事件、幂等、快照、库 | **全部加** | L1 |
| 20 | events-consistency §3.4、§5.3 | Python 的快照 / 幂等"等第一个用户再补" | 与 Go **同版本发布** | widget-py 必须过同一套 compconf；协议对等 |
| 21 | data-layer §0 | 外壳可以先用旧 SDK + INHERIT 组装 | 外壳在 SDK v0.6.x + NOINHERIT 上组装 | E11：全部在外壳之前做完 |
| 22 | foundations-communication §9.4 | Cron 时区配置键 `JOBS_TZ`，默认 UTC | 不加这个键。Cron 默认用 `BUSINESS_TIMEZONE`，每个任务可以写 `TZ` 覆盖 | 每日任务应按业务日历跑（F5） |
| 23 | foundations-data-platform §12.3 与 foundations-communication §5.4 | 两种错误体形状 | problem+json（RFC 9457）+ AIP-193 成员（§2 P4）。REST 上不再有 `error` 字段 | 一种形状；前端 06c 按 `domain:reason` 翻译 |
| 24 | foundations-communication §3.4 / §5.4 与 foundations-data-platform §2.4 | 池和出站舱壁满了，一说 `ResourceExhausted`，一说 `Unavailable` | 一律 `RESOURCE_EXHAUSTED` + `RetryInfo`，HTTP 映射为 429；reason 分开：池等待超时 `DB_POOL_EXHAUSTED`，出站舱壁满 `OUTBOUND_LIMIT`（与 foundations 15 一致） | 过载不该由服务配置自动重试（重试只针对 `UNAVAILABLE`）；与 R49 的 grpc-gateway 映射表一致 |
| 25 | foundations-data-platform §2.4 与 foundations-communication §3.2 T7 | 超时由角色级 `ALTER ROLE SET` 设，还是由 SDK `SET LOCAL` 设 | 两层都要：**SDK 每个事务 `SET LOCAL` 是保证**；be-ops 的角色级设置只兜底不走 SDK 的会话（psql、运维脚本） | 外壳里角色级设置不生效（T7） |
| 26 | foundations-communication §6.3 第 3 条与 data-lifecycle-v2 §4.7 | outbox 在线保留，一说 ≥ 30 天（作为回放的事实源），一说发布后 14 天 | **14 天**；更早的历史改走上游 `List` / 数据集 | 生命周期那一份更晚，并且考虑了擦除滞后（事件里有个人信息）；回放超过两周的事件，本来就该改成回填 |

本文**不重复**前文已经定了的机制细节（例如 authz 的 bundle v2 字段、`lifecycle.yaml` 的字段语义），只引用并给出它们在协议里的位置。

---

## 2. 组件协议 `be-protocol` 1.0

### 2.0 怎么读、什么叫"符合"

- 每条规则有三种等级。**MUST** 是必须做到，compconf 会测；**SHOULD** 是推荐，compconf 只警告；**INTERNAL** 是外面看不见、黑盒测不出来的保证（比如"事务里不许发网络调用"）。INTERNAL 规则在官方 SDK 里由 SDK 自己的测试守住；第四门语言的组件由作者在 `AGENTS.md` 里写明怎么守住，评审时核对。
- 每条规则后面括号里的 `CP-<组>-<号>`，是 compconf 里对应用例的 ID（§4.4）。
- "组件"同时指单独运行的进程，和外壳里的一个成员。凡是对外壳有额外要求的，集中写在 P19。
- 本章是规范正文的中文草稿。定稿时英文写进 `be-protocol/spec/`，章节号不变（P1–P20）。

### P1 进程与生命周期

| # | 规则 | 等级 |
|---|---|---|
| P1.1 | 镜像有两个入口：默认命令起服务；`component.yaml` 的 `migration.command` 跑迁移，退出 0 表示成功。迁移用同一个镜像、同一份配置，每次 `up` 都会重跑，所以必须幂等（P11）。官方 SDK 的约定是同一个二进制带子命令，`[./component, migrate, up]` 迁移、`[./component]` 起服务（CP-CORE-01） | MUST |
| P1.2 | 启动顺序固定：读配置并校验 → 开端口 → **在后台**连接 PG、总线、authz、JWKS。配置缺必填项或类型错，打一行 JSON 日志点名是哪个键，以退出码 **78**（EX_CONFIG）退出。依赖暂时不可达，就退避重试，**不退出**（CP-CORE-02、03） | MUST |
| P1.3 | `GET`/`HEAD /healthz` 只回答"进程活着"：返回 200，不碰 PG、总线、authz 或任何依赖（CP-CORE-04：套件停掉 PG 后它仍是 200） | MUST |
| P1.4 | `GET /readyz`：首次拿到 bundle、库身份探测通过（P10.7）、库里的迁移版本等于镜像的迁移版本，三者都满足时答 200；否则答 503，body 是 problem+json，`reason` 为 `NOT_READY` 并附 `metadata.waiting`。brickKit 支持 readiness 探针之前（§8 B3）不接进探针（CP-CORE-05） | SHOULD |
| P1.5 | 就绪之前，受保护路由答 503 + `AUTHZ_NOT_READY`；Public 路由照常服务（CP-AUTH-10） | MUST |
| P1.6 | 收到 SIGTERM：先停止接新请求；在途请求在 `SHUTDOWN_GRACE`（默认 20 s）内完成；再停后台工作，释放租约、对在途消息 ack 或 nak、把 outbox 当前批次收尾；最后退出 0（CP-CORE-06） | MUST |
| P1.7 | 可恢复的错误永不退出进程。所有后台工作都受监督：panic 被恢复，按 1 s → 5 min 退避重启，一个任务退出不影响其它任务。外壳和单跑行为完全相同（CP-JOBS-05、CP-SHELL-06） | MUST |
| P1.8 | 致命错误一律以**非 0** 退出：配置非法；库里的迁移版本高于镜像（迁移入口已经 WARN，服务入口拒绝启动）；外壳成员声明与编译进来的不一致。**不允许 `Start` 出错后以 0 退出**（今天的 Go 就是这样，§6.2 #37） | MUST |
| P1.9 | 镜像里有 `/bin/sh` 和 `wget`，因为健康检查经 shell 执行（现有易错点）（CP-CORE-07） | MUST |

### P2 配置

| # | 规则 | 等级 |
|---|---|---|
| P2.1 | 配置**只**来自平台注入：单跑时是进程环境，外壳里是本成员那一项的 `config`。键名就是环境变量名（brickKit 环境变量契约） | MUST |
| P2.2 | 组件只读自己 `configSchema` 里声明过的键，加上平台保留名（`COMPONENT_ID`、`COMPONENT_VERSION`、`*_ENDPOINT`、`PORT`）。官方 SDK 启动时读镜像里的 `component.yaml`，把 `Config` 限制在声明过的键上，读没声明的键直接报错 | MUST（INTERNAL 部分：只读声明的键） |
| P2.3 | 类型严格：整数、布尔、时长（Go duration 语法，如 `5s`、`15m`）、URL、JSON（结构化键）。值有、但解析不了，就当配置错误（P1.2），不静默回退到默认值（CP-CORE-02） | MUST |
| P2.4 | 不使用保留名做配置键，也不以 `_ENDPOINT` 结尾（brickKit 规则） | MUST |
| P2.5 | 可选依赖没装时，它的 `*_ENDPOINT` 变量**根本不存在**（不是空串）。组件必须降级，不能崩溃 | MUST |
| P2.6 | 读依赖地址时去掉 `http://` 和末尾的 `/`；gRPC 一律用带端口名的变量（`<DEP>_GRPC_ENDPOINT`） | MUST |
| P2.7 | 密钥类的值只经 `${VAR}` 或 `file://` 注入；日志、错误体、`/_be/info` 里都不出现它们的值 | MUST |

**协议级配置键**（组件按自己用到的 profile 写进 `configSchema`；be-protocol 发布一份 `schemas/config-keys.yaml`，门禁 `protocol-config-scan` 按它核对，§7.3）：

| 键 | 谁要 | 必填 | 默认 | 含义 |
|---|---|---|---|---|
| `PG_HOST` `PG_PORT` `PG_DATABASE` | 有库 | 是（PORT 否） | `5432` | 共享变量 |
| `PG_USER` `PG_PASSWORD` | 有库 | 是 | — | 本组件的登录角色，也是每个事务 `SET LOCAL ROLE` 的目标（R63）；口令是密钥 |
| `PG_SCHEMA` | 有库 | 是 | **无默认** | 不从角色推，也不在代码里写默认值 |
| `PG_POOL_MAX` | 有库 | 否 | `10` | 单跑时是池上限；外壳里是本成员在共享池里的并发预算（P10.5） |
| `PG_POOL_ACQUIRE_TIMEOUT` | 有库 | 否 | `5s` | 取连接的等待上限，超时答 `RESOURCE_EXHAUSTED`/`DB_POOL_EXHAUSTED` |
| `PG_CONN_MAX_LIFETIME` `PG_CONN_MAX_IDLE_TIME` | 有库 | 否 | `30m` / `5m` | — |
| `PG_MIGRATION_HOST` `PG_MIGRATION_PORT` | 有库 | 否 | 同 `PG_HOST` / `PG_PORT` | 用了 transaction 模式的 pooler 时，迁移要直连库 |
| `EVENT_BUS_URL` | 发或收事件 | 否 | 回退 `NATS_URL` | scheme 选适配器：`nats://`、`postgres://…?schema=be_bus`；`kafka://` 预留 |
| `NATS_URL` | 同上 | 二选一 | — | 共享变量 |
| `EVENTS_MAX_DELIVER` `EVENTS_BACKOFF` | 收事件 | 否 | `8` / `1s,10s,1m,5m,15m,30m,1h` | 部署层面的调优，**优先于**代码里的值；compconf 用它把重投缩短 |
| `AUTHZ_URL` | 有受保护路由 | 是 | — | authz 族的唯一地址（0107 推广）；取代 `AUTHZ_BUNDLE_URL` |
| `IAM_JWKS_URL` `IAM_ISSUER` | 同上 | 是 | — | 验签用的公钥地址；`iss` 的期望值 |
| `TENANT_ID` | 同上 | 是 | — | `aud` 的期望值（F1：一个部署就是一个租户） |
| `BUSINESS_TIMEZONE` | 用 Cron | 否 | `Asia/Shanghai` | 部署级默认时区，Cron 按它求值（F5）；法人自己的时区来自 mdm/org（P11.9） |
| `DATA_LIFECYCLE` | 有库 | 否 | `mode: on`，适配器都是 `none` | data-lifecycle-v2 §4.3 |
| `S3_URL` `S3_REGION` `S3_FORCE_PATH_STYLE` `S3_BUCKET` | 用对象存储 | 视情况 | — / `us-east-1` / `false` | foundations-data-platform §8.2 |
| `S3_ACCESS_KEY_ID` `S3_SECRET_ACCESS_KEY` | 同上 | 视情况 | — | 每个组件一套 |
| `OTEL_BASE_URL` | 全部 | 否 | 空 = 不导出 | OTLP/HTTP 的基础地址，SDK 自己补 `/v1/traces` |
| `LOG_LEVEL` | 全部 | 否 | `info` | `debug` / `info` / `warn` / `error` |
| `HTTP_DEFAULT_TIMEOUT` | 有 HTTP 路由 | 否 | `10s` | 入站默认截止时间（F13），路由可以自己声明 |
| `GRPC_MAX_CONNECTION_AGE` | 有 gRPC 端口 | 否 | `5m` | compconf 会把它缩短 |
| `SHUTDOWN_GRACE` | 全部 | 否 | `20s` | 应当小于平台的停机宽限（§8 B4） |
| `JOBS_OVERRIDES` | 有库 | 否 | 空 | JSON，按任务名覆盖 `interval` / `cron` / `enabled`；运维调优用，compconf 也用它把平台任务调快 |

brickKit 的 `config-schema-design` 一节提醒过："一个键装一整块 JSON"属于拆得太粗。`DATA_LIFECYCLE` 是有意的例外：它是结构化的声明，拆成平铺的键会多出几十个，而且没法表达"按表"。（法人日历不走配置：P2 答复后由 mdm/org 提供，见 P11.9。）这一点在 foundations 文档里写明。

### P3 HTTP 面（用户面 REST 与运维端点）

| # | 规则 | 等级 |
|---|---|---|
| P3.1 | 主端口（`deployment.port`）上的路径分三类，此外没有别的：用户面 `/{domain}/{name}/…`（经边缘路由，见 `edge_routes`）；运维面 `/healthz`、`/readyz`、`/metrics`、`/_be/info`（不进边缘）；资源契约 `/{domain}/{name}/_authz/*`、`/_shares/*`、`/_lifecycle/*`（经边缘，P6、P16）。BFF 例外，它的用户面是 `/graphql` | MUST |
| P3.2 | 请求 ID：入站带 `X-Request-Id` 就沿用（客户端伪造的那一份由边缘剥掉）；没有就用 trace-id。响应一律回写 `X-Request-Id`；所有出站调用都带上它（CP-CORE-10） | MUST |
| P3.3 | trace：入站提取 W3C `traceparent` 和 `baggage`；本次请求的 span 是它的子 span（CP-OBS-01） | MUST |
| P3.4 | 截止时间：每个路由有一个截止时间。默认取 `HTTP_DEFAULT_TIMEOUT`（10 s）；编排类路由声明 15 s；导出走异步，不占同步路由（F13）。到点答 504 + `DEADLINE_EXCEEDED`，同时取消下游调用和事务（CP-TIME-01） | MUST |
| P3.5 | 服务端超时：读请求头 5 s，读整个请求 30 s，写响应取"路由截止时间 + 5 s"，空闲连接 120 s。慢速请求头必须被断开（CP-CORE-08） | MUST |
| P3.6 | 请求体上限默认 1 MiB，路由可以声明更大（与 foundations 16 一致），超了答 413 + `BODY_TOO_LARGE`。上传一律走对象存储的预签名 URL（CP-CORE-09） | MUST |
| P3.7 | 写命令的幂等键可以放在 `Idempotency-Key` 请求头里，也可以放在 body 的 `idempotency_key` 字段里，两者等价；同时出现且取值不同，答 400（P13） | MUST |
| P3.8 | 列表分页用游标（0301，对齐 AIP-158）：参数 `page_size`（有上限，默认 50，最大 500；超过上限就降到上限）、`cursor`，返回 `next_cursor`（到末尾为空）。游标不透明，里面编码了排序键、最后一个 ID 和过滤条件的哈希；换了过滤条件还用旧游标，答 400 + `CURSOR_INVALID`。不返回精确总数 | MUST |
| P3.9 | 派生视图（投影、快照、ACL）的 List / Get 响应带 `X-Data-As-Of`，值是这份投影最近处理完的事件的 `occurred_at`（RFC 3339）（foundations-communication §4.6） | SHOULD |
| P3.10 | 访问日志：每个请求一行，`msg = http_request`，字段见 P18.2 | MUST |
| P3.11 | 不写 CORS。默认同源，由边缘负责 | MUST |
| P3.12 | `/metrics` 是 Prometheus 文本格式（P18.3）；`/_be/info` 见 P20 | MUST |

### P4 错误模型

**线上形状**（REST，`Content-Type: application/problem+json`，RFC 9457，扩展成员承载 AIP-193 的模型）：

```json
{
  "type": "urn:be:erp/inventory:INSUFFICIENT_STOCK",
  "title": "库存不足",
  "status": 400,
  "code": "FAILED_PRECONDITION",
  "reason": "INSUFFICIENT_STOCK",
  "domain": "erp/inventory",
  "detail": "产品 0192… 库存只有 2，需要 5",
  "metadata": { "product_id": "0192…", "requested": "5", "available": "2" },
  "violations": [ { "field": "items[0].qty", "reason": "MUST_BE_POSITIVE", "description": "…" } ],
  "instance": "/erp/sales/orders/0192…/confirm",
  "request_id": "4bf9…",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
}
```

字段集合与 foundations 15（`docs/zh/04-foundations/15-user-api-and-errors.md`）完全一致，以那份为准；**没有 `error` 别名**（F3：3.0.0 一次性重建，不做兼容层）；重试延迟只走 `Retry-After` 响应头（来自 gRPC 的 `RetryInfo`），错误体里不再放 `retry_after_ms`。

| # | 规则 | 等级 |
|---|---|---|
| P4.1 | 组件的每个 4xx/5xx 都是这个形状。`reason` 是 UPPER_SNAKE。`domain` 就是组件 ID，原样不变（`erp/inventory`），`type` 是 `urn:be:<domain>:<reason>`；SDK 自己的 reason 用 `domain: "be"`（CP-ERR-01） | MUST |
| P4.2 | gRPC 上：标准状态码 + `google.rpc.ErrorInfo{reason, domain, metadata}`，按需再附 `BadRequest`、`PreconditionFailure`、`RetryInfo`、`ResourceInfo`。REST 与 gRPC 之间按 grpc-gateway 的表互相映射（R49：InvalidArgument / FailedPrecondition / OutOfRange → 400，AlreadyExists / Aborted → 409，NotFound → 404，ResourceExhausted → 429，Unavailable → 503，DeadlineExceeded → 504）（CP-ERR-02） | MUST |
| P4.3 | `INTERNAL`、`UNKNOWN`、`DATA_LOSS` 一律只返回一句通用文案 + `trace_id`，原始错误只进日志。SQL 错误、栈、token 解析失败的原文都不进响应（CP-ERR-03） | MUST |
| P4.4 | 每个组件在 `contracts/errors.yaml` 登记自己的 reason，字段是 `{reason, code, http, params[], title: {zh, en}, message: {zh, en}, since, deprecated}`（与 foundations 15 一致）。只增不改，规则同 `permissions.tsv`。前端用它生成 i18n 文案表，服务端不翻译 | MUST |
| P4.5 | GraphQL（BFF）：`errors[].extensions = {code, reason, domain, metadata, request_id, trace_id}`（与 foundations 15 一致） | MUST |
| P4.6 | 日志级别按状态码定（R51）：Internal / Unknown / DataLoss 记 ERROR；Unavailable / DeadlineExceeded 记 WARN；调用方错误记 INFO；停机时的 Canceled 不记 | MUST |

**保留的 SDK reason**（`domain: be`，be-protocol 的 `schemas/errors-be.yaml`）。下表与 foundations 15 的平台 reason 表逐行相同（两份文档的并集，一个含义一个名字：池等待超时是 `DB_POOL_EXHAUSTED`、出站舱壁满是 `OUTBOUND_LIMIT`，不再有 `BULKHEAD_FULL`；缺功能键是 `MISSING_PERMISSION`；游标不匹配是 `CURSOR_INVALID`；重试用尽的事务冲突是 `TX_CONFLICT`）：

| Reason | Code | 什么时候抛 |
|---|---|---|
| `INTERNAL` | `INTERNAL` | 任何内部错误，原始错误被隐藏 |
| `TOKEN_STALE` | `UNAUTHENTICATED` | token 早于一次角色变更 |
| `MISSING_PERMISSION` | `PERMISSION_DENIED` | 调用方缺少某个权限键 |
| `NOT_FOUND` | `NOT_FOUND` | 记录不存在或不可见 |
| `AUTHZ_NOT_READY` | `UNAVAILABLE` | 权限 bundle 还没加载 |
| `NOT_READY` | `UNAVAILABLE` | 进程还没就绪：还没拿到 bundle、库身份探测没通过，或库里的迁移落后于镜像（`/readyz`） |
| `TOKEN_INVALID` | `UNAUTHENTICATED` | 没有 token，或 token 校验不过（签名、`iss`、`aud`、`typ`、过期） |
| `UNSUPPORTED_DELEGATION` | `UNAUTHENTICATED` | token 经由一种 provider 不支持的代理方行事 |
| `MISSING_CALLER` | `UNAUTHENTICATED` | 系统面调用没带 `be-caller`（[14](../../../docs/zh/04-foundations/14-system-rpc.md)） |
| `OUT_OF_SCOPE` | `PERMISSION_DENIED` | 请求参数本身就是一个维度取值，且不在调用方的范围内（`warehouse_id=7`） |
| `FIELD_FORBIDDEN` | `PERMISSION_DENIED` | 写了一个调用方看不到的字段 |
| `SORT_FORBIDDEN` | `INVALID_ARGUMENT` | 按对调用方掩码的字段排序、过滤或聚合 |
| `SHARE_NOT_ALLOWED` | `PERMISSION_DENIED` | 这个资源类型或这个调用方不允许做的分享（[20](../../../docs/zh/04-foundations/20-authorization-provider.md)） |
| `CAPABILITY_UNAVAILABLE` | `UNIMPLEMENTED` | 装的 provider 或适配器缺某项能力；`metadata.capability` 写明是哪项 |
| `IDEMPOTENCY_MISMATCH` | `INVALID_ARGUMENT` | 一个键被复用在别的命令、目标或请求体上 |
| `IDEMPOTENCY_IN_PROGRESS` | `ABORTED` | 这个键的第一次使用还没结束 |
| `CURSOR_INVALID` | `INVALID_ARGUMENT` | 游标与请求不匹配 |
| `BATCH_TOO_LARGE` | `INVALID_ARGUMENT` | ID 数超过一个批次允许的数量 |
| `LOCK_TIMEOUT` | `ABORTED` | 锁等待超过了 `lock_timeout`（[10](../../../docs/zh/04-foundations/10-local-transactions.md#端口契约)） |
| `STATEMENT_TIMEOUT` | `DEADLINE_EXCEEDED` | 一条语句或一个事务超过了它的超时 |
| `TX_CONFLICT` | `ABORTED` | 自动重试之后序列化失败仍然存在 |
| `DB_POOL_EXHAUSTED` | `RESOURCE_EXHAUSTED` | 成员的连接预算一直满到截止时间 |
| `OUTBOUND_LIMIT` | `RESOURCE_EXHAUSTED` | 对同一个依赖的并发调用太多（[16](../../../docs/zh/04-foundations/16-deadlines-and-retries.md)） |
| `DEADLINE_BUDGET_EXHAUSTED` | `DEADLINE_EXCEEDED` | 剩余时间太少，不足以发起调用 |
| `BODY_TOO_LARGE` | `INVALID_ARGUMENT` | 请求体超过路由的上限；以 HTTP 413 回答（[16](../../../docs/zh/04-foundations/16-deadlines-and-retries.md)） |
| `RANGE_COLD` | `FAILED_PRECONDITION` | 请求的时间范围已转入冷存储；`metadata` 给出冷区间，以及能否解冻、能否异步导出 |
| `UNIT_SEALED` | `FAILED_PRECONDITION` | 修改一个已封存的生命周期单元；应当新建一张冲销单据 |

### P5 身份：JWT 验证

| # | 规则 | 等级 |
|---|---|---|
| P5.1 | 请求头写法是 `Authorization: Bearer <jwt>`。缺失或格式不对，答 401 `TOKEN_INVALID`（CP-AUTH-01） | MUST |
| P5.2 | `alg` 只接受白名单里的 `RS256`、`ES256`、`EdDSA`，而且必须等于 JWKS 里那把钥匙的 `alg`。`kid` 必填（CP-AUTH-02） | MUST |
| P5.3 | 必填的 claim：`iss` 等于 `IAM_ISSUER`；`aud` 包含 `TENANT_ID`；`typ` 等于 `"access"`，`refresh` 和缺失一律拒收；`sub` 非空；`exp`、`iat`、`jti` 都有；有 `nbf` 时检查。时钟偏差容忍 60 s（CP-AUTH-03…06：刷新令牌、错的 iss、错的 aud、没有 exp，各一条） | MUST |
| P5.4 | JWKS：本地缓存，最长 1 h；遇到不认识的 `kid` 时刷新一次，最多每 30 s 一次；拉取超时 3 s；拉取失败沿用旧钥匙（fail-static）。轮换期间新旧两把钥匙签的 token 都能验过（CP-AUTH-07） | MUST |
| P5.5 | 认识的 claim 包括 `sub`、`tenant_id`、`roles[]`、`dept_path`、`act{sub, kind, act}`、`ceil[]`、`dg`、`azp`、`locale`。`org_id` 弃用，读但不用。`act.kind` 的枚举里有 `agent`；bundle 能力 `agents=false` 时，带 `act.kind=agent` 的 token 答 401 `UNSUPPORTED_DELEGATION`（A4：只占位） | MUST |
| P5.6 | stale：`iat` 早于 `stale_since[sub]` 减 5 s，答 401，带响应头 `WWW-Authenticate: Bearer error="token_stale"`，`reason` 为 `TOKEN_STALE`（CP-AUTH-08） | MUST |
| P5.7 | 服务账号的 `sub` 写成 `svc:<id>`，带角色，走和用户相同的判定（扩展点，现在没有签发方） | MUST（会读） |
| P5.8 | 原始 token 只存在请求上下文的私有槽里，供 `UserHTTP` 转发；不进 `User` 对象，不进日志 | INTERNAL |

### P6 授权：bundle、范围、资源契约、投影

provider 契约（bundle v2、changes、Check、WriteTuples）归族契约仓库 `contract-infra-authz`（authz-architecture §3）。本章只规定**组件一侧**怎么消费它、怎么求值、对外挂出什么。

| # | 规则 | 等级 |
|---|---|---|
| P6.1 | bundle：`GET {AUTHZ_URL}/authz/v2/bundle`，带 `If-None-Match` / ETag。每 15 s 轮询一次；首次拉取失败按 0.5 s 起步、翻倍、上限 15 s 退避；单次超时 3 s；收到 `infra.authz.changed.v1` 的 poke 立刻拉一次；拉取失败沿用旧 bundle（fail-static）。`contract` 不是 `authz/2.*` 时拒绝使用，并记 ERROR | MUST |
| P6.2 | 路由判定链：Public 直接放行 → 验签（P5）→ stale → Authenticated 到此放行 → 还没拿到过 bundle 答 503 → 委托和天花板（`act`、`ceil`、`dg`）→ 功能键不在角色并集里答 403 `MISSING_PERMISSION`（`metadata.permission`）→ 放行，并把 `Access` 放进上下文。每个业务路由必须声明一个守卫（权限键、Public 或 Authenticated），没有"忘了写"这种状态（CP-AUTH-09…12） | MUST |
| P6.3 | 档位：`own < dept < subtree < all`（I2 改判，`dept` 现在就加）。对路由键 K，取所有授予 K 的角色里档位最高的那个；授予了 K 但没写档位，取角色的 `default_level`；还没有就是 `own`。资源维度的取值，按键取所有角色的并集；`*` 只能显式授予，表示全部；一个都没有就什么都看不到。`until` 按本地时间判定（CP-SCOPE-01…05） | MUST |
| P6.4 | 主体集合：`S(P) = {user:sub} ∪ {role:r} ∪ {dept:dept_path} ∪ {dept_tree:p \| p 是 dept_path 的祖先或自身} ∪ ⋃S(委托人)`。**R60**：`dept_path` 为空或格式不对时，两个 dept 项都不出现，部门数组为空，什么都匹配不到。只有 `"/"` 表示整棵树。"空串当根"永远不成立（CP-SCOPE-06） | MUST |
| P6.5 | 列表 SQL 用**规范谓词**，参数名固定：`@s_all`、`@s_owners[]`、`@s_dept_exact[]`、`@s_dept_prefix[]`（已经拼好 `%`、已转义）、`@s_<dim>_all`、`@s_<dim>_ids[]`、`@s_acl`、`@s_relations[]`、`@s_subjects[]`、`@s_graph_ids[]`。SQL 形状照抄 authz-architecture §3.5，仍然是静态参数化 SQL，没有 RLS（0206） | MUST（形状 INTERNAL；结果由 CP-SCOPE 测） |
| P6.6 | 单条记录判定：`Can(key, row)` 给出 `{visible, allowed, reason}`。**看不见**（规则、共享、派生都不成立）时，读和命令一律 **404**（A3 细化 R62）。看得见但做不了，答 403，带 `reason`。只有请求参数本身就是维度值时（`warehouse_id=7`）才答 403 `OUT_OF_SCOPE`（CP-SCOPE-07…09） | MUST |
| P6.7 | **List 和 Can 一致**：一行出现在列表里，当且仅当对同一个路由键 `Can` 为 visible（CP-SCOPE-10，属性测试） | MUST |
| P6.8 | 字段级权限：`type: field` 的键。没有读键的字段在**源头**置为 null，并列进响应的 `_masked[]`；按掩码字段排序、过滤、聚合，答 400 `SORT_FORBIDDEN`；改了掩码字段，答 403 `FIELD_FORBIDDEN`（CP-SCOPE-11） | MUST（声明了字段键的组件） |
| P6.9 | 行按钮：列表响应里每一行带 `_access: {<action>: bool}`，前端不自己拼规则 | SHOULD |
| P6.10 | 资源契约。声明了 `resources` 的组件，SDK 自动挂出三组端点：`POST /{d}/{n}/_authz/check`（一次最多 500 条，返回 `[{visible, allowed, reason}]`）；`GET /{d}/{n}/_authz/explain?key=&type=&id=`（受 R62 约束：对看不见的记录只答本人一侧的事实）；`GET\|POST\|DELETE /{d}/{n}/_shares/{type}/{id}[/{share_id}]`。provider 缺某项能力时，答 501 `CAPABILITY_UNAVAILABLE`，并在 `metadata.capability` 里写能力名（CP-SCOPE-12…14） | MUST |
| P6.11 | 一致性令牌：入站带了 `X-Authz-Revision: N`，而本地投影的水位低于 N，就同步拉一次 changes（预算 300 ms）。还追不上：单条读回落到 provider 的 Check；列表照常返回，加响应头 `X-Authz-Consistency: stale`。`_shares` 写入后，等自己的投影追上返回的 revision 再响应（CP-SCOPE-15） | MUST（`sharing` 能力为真时） |
| P6.12 | ACL 投影：放在本组件 schema 的 `besdk_authz_acl` / `besdk_authz_cursor` 里（附录 A），只给声明了 `resources` 的组件建。拉取：`GET {AUTHZ_URL}/authz/v2/changes?types=…&after=<rev>&limit=500`，每 5 s 一次，收到 poke 时立刻拉；遇到 `410` 就用 `ReadTuples` 快照重建。只拉本组件声明的类型，以及它 `inherits` 的外部类型。**投影里只有直接元组**，主体一侧的展开在查询时现算 | MUST |
| P6.13 | 组件主责的关系（如商机团队）：在业务事务里调 `tx.SyncRelation(type, id, relation, subjects, version)`，写进 outbox，subject 是 `infra.authz.relation.sync.v1`。不直接调 `WriteTuples` | MUST |
| P6.14 | 决策不跨请求缓存：远程 Check 的结果只在本次请求内记住；`_authz/check` 的调用方不缓存结果（0201、authz-architecture §4.3） | INTERNAL |

### P7 系统面：组件之间的 gRPC

| # | 规则 | 等级 |
|---|---|---|
| P7.1 | gRPC 是组件之间的**系统协议**（0208）：不经边缘，不进 `edge_routes`。用户在用户请求路径上要读别的组件的受限数据，一律走用户面 REST（P8） | MUST |
| P7.2 | 出站 metadata：`traceparent` 和 `baggage`（OTel 注入）、`x-request-id`、`be-caller`（**必填**，本成员的组件 ID）、`be-actor-sub`（ctx 里有用户时填，每次调用现取）、`be-actor-act`（有代理链时，JSON 形式）。入站缺 `be-caller`，答 `UNAUTHENTICATED` + `MISSING_CALLER`（CP-RPC-01、02） | MUST |
| P7.3 | 服务端身份：上下文里标成系统主体 `System{Caller, ActorSub}`。面向用户的方法从 gRPC 进来，答 `UNAUTHENTICATED`，不是 Internal，也不 panic（CP-RPC-03） | MUST |
| P7.4 | 服务端拦截器顺序：recovery → 身份 → 截止时间下限（入站没带 `grpc-timeout` 时补 10 s）→ BatchGet 上限 → 错误详情规范化 → RED 指标 → trace。一元和流各一条链 | MUST（顺序 INTERNAL） |
| P7.5 | 服务端参数：`MaxRecvMsgSize` 显式设为 4 MiB；`MaxConnectionAge` 取 `GRPC_MAX_CONNECTION_AGE`（默认 5 min），`MaxConnectionAgeGrace` 30 s；`EnforcementPolicy.MinTime` 20 s（CP-RPC-04、05） | MUST |
| P7.6 | 客户端连接按（成员，依赖，端口）复用，懒建。稳态下对同一个依赖只有一条 TCP 连接。keepalive：每 30 s 一次，超时 10 s，空闲时不发 ping（CP-OUT-01） | MUST |
| P7.7 | 出站截止时间：取 `min(3 s, 剩余预算 − 50 ms)`；剩余预算不足 50 ms 时**不发出调用**，直接答 `DEADLINE_EXCEEDED` + `DEADLINE_BUDGET_EXHAUSTED`（CP-OUT-02） | MUST |
| P7.8 | 重试：方法标了 `idempotency_level = NO_SIDE_EFFECTS` 或 `IDEMPOTENT` 的，在 `UNAVAILABLE` 时重试，最多 3 次，退避 50 ms 起、上限 500 ms、倍数 2。其它方法只做透明重试（请求从未发出时）。重试预算用 `retryThrottling{maxTokens: 10, tokenRatio: 0.1}`，按连接计算，所以也是按成员计算。带 `idempotency_key` 字段的 rpc 必须标 `IDEMPOTENT`，由门禁检查（CP-OUT-03、04） | MUST |
| P7.9 | 出站舱壁：每个成员对每个依赖最多 64 个并发调用，超了立刻答 `RESOURCE_EXHAUSTED` + `OUTBOUND_LIMIT`（CP-OUT-05） | MUST |
| P7.10 | BatchGet 上限：proto 字段选项 `[(be.v1.max_items) = N]`，没写就是 500。超限答 `INVALID_ARGUMENT` + `ErrorInfo{reason: BATCH_TOO_LARGE, metadata: {field, max, got}}` + `BadRequest`。调用方用 `BatchGetAll` 自动分片（D8）（CP-RPC-06） | MUST |
| P7.11 | 不做流式；不压缩，超过 1 MiB 的响应可以按调用开 gzip；proto 包名 `<domain>.<name>.v<n>`，只增（0302） | MUST |

### P8 出站：用户面 HTTP 与第三方 HTTP

| # | 规则 | 等级 |
|---|---|---|
| P8.1 | `UserHTTP(dep)`：只能在有用户的上下文里用。它转发调用者原始的 `Authorization`，以及 `X-Request-Id`、`traceparent`、`X-Authz-Revision`。上下文里没有用户（事件 handler、gRPC 系统调用里）就返回 `UNAUTHENTICATED`，**绝不悄悄换成系统身份**（CP-OUT-06） | MUST |
| P8.2 | `UserHTTP` 的超时同 P7.7；只有 GET 在连接被重置时重试一次；对方回的 problem+json 被还原成同样的状态码和 reason | MUST |
| P8.3 | `ExternalHTTP(name)` 调第三方（钉钉、Casdoor 这类）：默认超时 10 s，可以按名字配置；有 trace 和指标；**不转发**任何内部头（`Authorization`、`be-*`、`X-Authz-*`） | MUST |
| P8.4 | 事务里不许发网络调用：上下文带着"在事务里"标记时，SDK 的 `Conn`、`UserHTTP`、`ExternalHTTP` 都返回 `ErrNetworkInTx`，测试构建里直接 panic。事务里想触发对外动作，只有 `tx.Publish` 和 `tx.Enqueue` 两条路 | INTERNAL |

### P9 截止时间与重试预算（汇总）

| 层 | 默认 | 规则来源 |
|---|---|---|
| 边缘 | 路由截止时间 + 5 s，与路由由同一处声明生成 | foundations 16 |
| 入站 HTTP | 10 s；编排类路由 15 s | F13 |
| 入站 gRPC | 取 `grpc-timeout`；没带时 10 s | P7.4 |
| 出站 RPC 和 UserHTTP | `min(3 s, 剩余 − 50 ms)` | P7.7 |
| SQL 语句 | `min(5 s, 剩余)` | P10.3 |
| 锁等待 | 2 s | P10.3 |
| 事务里空闲 | 30 s | P10.3 |
| 事件 handler | AckWait（30 s）− 5 s | P12 |
| Job 单次运行 | 由 `Job.Timeout` 声明，必填 | P14 |
| 事务重试 | 只对 40001 / 40P01，最多 3 次，`10 ms · 2^n` 加抖动 | P10.4 |
| RPC 重试 | 只对幂等方法的 UNAVAILABLE；预算是额外流量 ≤ 10 % | P7.8 |

规则原文写进文档："子调用的超时必须短于调用方愿意等你的时间"（brickKit `09-patterns/04-service-calling`）。

### P10 数据库：身份、事务、池

| # | 规则 | 等级 |
|---|---|---|
| P10.1 | 库身份只来自配置：`PG_USER` 是每个事务都要切换到的角色，`PG_SCHEMA` 是 schema，两者都必填，没有默认值，也不互相推导。代码、迁移、测试夹具里都不出现 `_rw`、`_archive`、`shell_` 这类派生名，也不出现本组件的 schema 或角色字面量（R63）（CP-DB-01：套件用随机 schema、随机角色、NOINHERIT 的外壳角色跑完全部 profile） | MUST |
| P10.2 | 每一次数据库访问都在事务里，并且开头先执行 `SET LOCAL ROLE <PG_USER>` 和 `SET LOCAL search_path TO <PG_SCHEMA>`。这包括业务事务、outbox 泵、消费、Jobs、生命周期、投影拉取和启动探测，没有例外。search_path 里不再放 `_archive`（D2）。会话级的 `SET` 一律禁止 | MUST（INTERNAL） |
| P10.3 | 每个事务都用 `SET LOCAL` 设三个超时：`statement_timeout = min(5 s, 剩余预算)`、`lock_timeout = 2 s`、`idle_in_transaction_session_timeout = 30 s`。服务端 ≥ 17 时再按剩余预算设 `transaction_timeout`。会话时区永远是 UTC（CP-DB-02：套件先持锁，被测组件在 `lock_timeout` 内答 409 + `LOCK_TIMEOUT`） | MUST |
| P10.4 | 隔离级别默认 READ COMMITTED，单个事务可以选 RR 或 SERIALIZABLE。40001 / 40P01 由 SDK 回滚，重新执行整个事务函数，最多 3 次。用尽后答 `ABORTED` + `TX_CONFLICT`。55P03 映射成 `ABORTED` + `LOCK_TIMEOUT`，57014 映射成 `DEADLINE_EXCEEDED` + `STATEMENT_TIMEOUT`，53300 映射成 `UNAVAILABLE` | MUST |
| P10.5 | 池：单跑时的上限是 `PG_POOL_MAX`。外壳里物理池的大小取 `min(Σ 成员的 PG_POOL_MAX, 外壳自己的 PG_POOL_MAX)`，每个成员再挂一个容量为它自己 `PG_POOL_MAX` 的信号量。取不到连接时最多等 `PG_POOL_ACQUIRE_TIMEOUT`，超时答 `RESOURCE_EXHAUSTED` + `DB_POOL_EXHAUSTED`。一个成员耗尽，不影响别的成员（CP-DB-03：套件压满并发，`pg_stat_activity` 里属于该角色的连接数 ≤ `PG_POOL_MAX`） | MUST |
| P10.6 | 一个执行流同一时刻最多占一条连接：已经在事务里，再开事务就返回 `ErrNestedTx`；消费 handler 的 `Apply` 拿到的就是 SDK 的那个事务。这是池饥饿的根治办法 | INTERNAL |
| P10.7 | 启动探测在后台跑，不放进 `/healthz`：`has_schema_privilege(current_user, current_schema(), 'USAGE,CREATE')`；schema 里不存在属主不是 `PG_USER` 的表；`server_version_num ≥ 140000`；支持声明式分区和 `SKIP LOCKED`。失败时记 ERROR，`be_db_identity_ok = 0`，`/readyz` 答 503 | MUST |
| P10.8 | advisory 锁只用事务级的，键是 `pg_advisory_xact_lock(hashtext(current_schema() \|\| ':' \|\| name), hashtext(key))`。所以外壳里成员之间不会撞键，"单跑和外壳同时在跑"时，同一个 schema 自然互斥。会话级锁一律禁止（与 pgbouncer 的 transaction 模式兼容） | MUST（INTERNAL） |
| P10.9 | 队列认领、幂等认领都是原子的：`FOR UPDATE SKIP LOCKED`，或者 `INSERT … ON CONFLICT DO NOTHING / DO UPDATE … WHERE … RETURNING`。先 `SELECT` 再写，一律禁止（现有易错点） | MUST |
| P10.10 | 一个事务要锁多行时，按主键或业务唯一键的固定顺序加锁（库存多品预留，foundations-communication §3.4 第 5 条） | MUST（组件义务） |

### P11 迁移与数据形状

| # | 规则 | 等级 |
|---|---|---|
| P11.1 | 迁移以 `PG_USER` 登录，直连库（有 `PG_MIGRATION_HOST` 就用它）。会话参数 `lock_timeout = 5 s`、`statement_timeout = 15 min`。拿锁超时就退避重试 3 次，失败时打出阻塞者的 pid 和 SQL（截前 200 字） | MUST |
| P11.2 | 迁移文件里不出现 `OWNER TO`、`GRANT`、`REVOKE`、`CREATE SCHEMA`、`CREATE ROLE` / `ALTER ROLE`、`SET`，不出现限定名，不出现角色或 schema 字面量，也不出现日期字面量的分区。名字都不带限定，靠 search_path 解析（R63、data-layer §2.6） | MUST |
| P11.3 | 迁移的状态表放在本组件的 schema 里（表名由各语言的工具决定）。组件迁移跑完之后，SDK 再跑一段**平台迁移**，内容依次是：建或升级 `besdk_*` 表（版本记在 `besdk_platform_version`）；按 `lifecycle.yaml` 建出当前分区窗口；确保事件流和本组件的 durable 存在（P12.4）。三者都幂等 | MUST |
| P11.4 | 演进遵守 expand / contract：contract 类迁移的文件头写 `-- be:contract after=<version>`；`CREATE INDEX CONCURRENTLY` 单独一个文件，文件头写 `-- be:no-transaction`。生产只前滚（foundations-data-platform §6.4） | MUST |
| P11.5 | 自有主键一律 UUIDv7，列类型 `uuid`，由应用生成。分区表的 `created_at` 必须等于 `IDTime(id)`。外部引用保持 `TEXT`（F3）。线上仍是不透明字符串 | MUST |
| P11.6 | 金额 `NUMERIC(19,4)`；单价、成本、数量 `NUMERIC(19,6)`；汇率 `NUMERIC(19,10)`。金额与币种 `CHAR(3)` 总是成对出现。舍入只在 SDK 的 money 包里做，按 ISO 4217 的小数位，默认 HALF_AWAY_FROM_ZERO。线上仍是十进制字符串（0301）（F4） | MUST |
| P11.7 | 瞬时用 `timestamptz`；业务日期用 `DATE`，按**法人**的业务时区算。SQL 里禁止 `CURRENT_DATE`、`now()::date` 和 `date_trunc(…, now())`，"今天"由 SDK 算出来作为参数传入。事件带单据的业务日期（F5） | MUST |
| P11.8 | 交易单据表带 `legal_entity_id TEXT NOT NULL`；事件 payload 也带它。缺法人的事件，消费方拒收（进 DLQ），不悄悄记进 `default`（F2、Q2） | MUST |
| P11.9 | 法人日历：时区、会计年度起始月、本位币，来自 `mdm/org`，由 SDK 的快照帮手维护；汇率来自 `mdm/currency`。两者本轮新建，排在其余组件升 3.0.0 之前（用户答复 P2），所以没有过渡用的 `LEGAL_ENTITIES` 共享变量，汇率也不限定为 1。mdm/org 与 IAM 目录（部门）怎么分工，在 mdm/org 自己的设计里定 | MUST |
| P11.10 | 单据编号：`besdk_number_series` 表，`tx.NextNumber(series)`。凭证这类 `gapless=true` 的，在同一事务里锁行，按期连续、无缺号（F8，每个法人串行，吞吐上限写进文档）；其余按块预取，允许缺号。格式由组件配置给出（`<NAME>_NO_FORMAT`） | MUST |
| P11.11 | 业务表、迁移里的表，都在 `lifecycle.yaml` 里有声明（P16） | MUST |

### P12 事件

**信封**（CloudEvents 1.0 二进制模式；NATS 用 header，PG 队列用列，Kafka 用 header）：

| 头 | 值 | 谁填 |
|---|---|---|
| `ce-specversion` | `1.0` | SDK |
| `ce-id` | UUIDv7，也就是 `besdk_outbox.id`；同时作为 `Nats-Msg-Id` | SDK |
| `ce-source` | 生产者的组件 ID | SDK |
| `ce-type` | subject，如 `erp.sales.order.confirmed.v1` | 业务 |
| `ce-time` | 发生时刻，RFC 3339 UTC | SDK |
| `ce-subject` | 聚合 ID | 业务 |
| `content-type` | `application/json`（CloudEvents 二进制模式里 datacontenttype 就是这个头，与 foundations 13 一致） | SDK |
| `ce-dataschema` | `<component>@<version>/contracts/events/<file>#<subject>`（引用，不是可下载的 URL） | SDK |
| `ce-aggregatetype` | 契约里的 `x-aggregate-type`（如 `erp.sales.order`） | SDK（从契约查） |
| `ce-aggregateversion` | 聚合版本，同一个聚合类型的所有 subject 共用一个单调序列 | 业务 |
| `ce-causationid` | 引起它的那条事件的 `ce-id`（在 handler 或 Job 里发布时） | SDK（从 ctx 取） |
| `ce-hopcount` | 来源事件的值 + 1；从用户请求发出的是 0 | SDK |
| `ce-legalentity` | 交易单据事件必填（P11.8） | SDK（从 payload 取） |
| `traceparent` | W3C | SDK |

| # | 规则 | 等级 |
|---|---|---|
| P12.1 | 发布只经 outbox：和业务写入在**同一个事务**里写 `besdk_outbox`。泵在事务外发布，拿到持久化确认（JetStream 的 PubAck）后才标成 `PUBLISHED`；总线不可用时行留在 `PENDING`，按 `next_attempt_at` 退避（1 s → 1 min），**永不丢弃**，积压由告警发现。认领用 `SKIP LOCKED`。轮询间隔自适应：忙时 200 ms，空闲时退到 2 s。最多 256 个确认同时在途（CP-EVP-01…04：停掉总线 → 执行命令仍然成功 → 恢复总线 → 事件送达，不丢、不重） | MUST |
| P12.2 | payload 是 JSON，用 `contracts/events/*.json`（JSON Schema）校验，契约里写明 `x-aggregate-type` 和 `x-consumption: state\|sequence`；建议 ≤ 64 KiB，硬上限 1 MiB，更大的走对象存储 claim-check。payload 里不放给人看的敏感字段（CP-EVP-05） | MUST |
| P12.3 | subject 命名：`<domain>.<aggregate>.<action>.v<n>`。历史上的 `sales.*`、`finance.*` 保留（E10）。同一个聚合类型的所有 subject 共用一个单调递增的版本 | MUST |
| P12.4 | 流：按 subject 第一段，名叫 `BE_<第一段大写>`，subjects 是 `<第一段>.>`；默认 7 天、1 GiB、丢旧、去重窗口 10 min、文件存储、单副本；DLQ 流 `BE_DLQ` 保留 30 天。规则是"没有就建，有就不碰"，在平台迁移和启动时各执行一次（E1、E2） | MUST |
| P12.5 | durable：每个（组件，subject）一个 pull 消费者，名字是 `<组件ID的/换成_>__<subject的.换成_>`。参数：AckWait 30 s，MaxAckPending 256，MaxDeliver 和 BackOff 取 P2 的键，首次建时 `DeliverAll`（E3），InactiveThreshold 30 天。单跑、进外壳、多副本，用的都是同一个 durable（CP-EVS-01） | MUST |
| P12.6 | 去重靠**聚合流游标**：`besdk_event_cursor` 的主键是 `(consumer, aggregate_type, aggregate_id)`，推进游标和业务写入在同一个事务里（附录 A 的 upsert）。语义是"状态模式"：比游标旧的版本直接跳过，handler 要写成"把聚合推进到第 v 版"。乱序和重复投递之后，最终状态与按序投递一次相同（CP-EVS-02、03，属性测试） | MUST |
| P12.7 | 两种 handler：`Apply` 在游标所在的事务里，只做本地写；`Run` 在事务外执行，可以走网络，成功后用一个短事务推进游标，必须按业务键幂等。handler 出错就 Nak，按退避重投；`Permanent` 错误直接进 DLQ；最后一次投递仍失败也进 DLQ。DLQ 的 subject 是 `dlq.<durable>.<原 subject>`，带原来的 `ce-*` 头和 `be-dlq-reason`、`be-dlq-consumer`、`be-dlq-delivery`（CP-EVS-04、05） | MUST |
| P12.8 | `ce-hopcount > 10` 直接进 DLQ（防环）。在 handler 或 Job 里发布的事件，`causationid` 和 `hopcount` 自动派生（CP-EVS-06） | MUST |
| P12.9 | 处理慢时每过 AckWait/3 发一次 `InProgress`。每个订阅默认 4 个并发，同时受本成员 DB 预算的约束。正确性永远不依赖 broker 的顺序 | MUST |
| P12.10 | 即时信号（poke），比如 `infra.authz.changed.v1`：尽力而为，可以丢，不持久、不重投。外壳里每个成员各订阅一次 | MUST |
| P12.11 | 回放分三档：①流的保留期（7 天）以内，建一个从指定时间开始的临时消费者；②超过流的保留期、仍在 outbox 的保留期（发布后 14 天，data-lifecycle-v2 §4.7）以内，从生产者的 outbox 重发，`Nats-Msg-Id` 加后缀避开去重窗口，消费者靠游标去重（`make events-replay`）；③更早的历史不再重放事件，新消费者走上游的 `List` 回填（P15.3），遇到 `RANGE_COLD` 就改读上游发布的数据集 | MUST（生产者保留 outbox 14 天） |
| P12.12 | 总线适配器由 `EVENT_BUS_URL` 的 scheme 选：`jetstream`（默认）、`pgqueue`（schema `be_bus`，由 db-init 建）、`kafka`（预留）。适配器必须通过 `tools/be-acceptance/conformance/bus/`（busconf，§4.8） | MUST |

### P13 命令幂等

| # | 规则 | 等级 |
|---|---|---|
| P13.1 | 有副作用的写命令（REST 和 gRPC 都算）接受幂等键（P3.7）。键在 **caller 命名空间**里生效：caller 是 `user:<sub>`、`svc:<be-caller>` 或 `system`（本组件自己的后台任务） | MUST |
| P13.2 | 绑定三样东西：`command`（权限键或 rpc 全名）、`target`（命令作用的聚合 ID；建类命令为空）、`request_hash`（声明参与指纹的字段，按 RFC 8785 JCS 规范化后取 sha256）。同一个 caller、同一个键，这三样里任何一样不同，答 400 / `INVALID_ARGUMENT` + `IDEMPOTENCY_MISMATCH`（CP-IDEM-02…04） | MUST |
| P13.3 | 第一次认领之后、完成之前（两段式命令）再用同一个键，答 409 / `ABORTED` + `IDEMPOTENCY_IN_PROGRESS`。重放返回第一次的结果，状态码相同（CP-IDEM-01、05） | MUST |
| P13.4 | 不同 caller 用同一个键，互不可见、互不影响，也不给出"这个键存在"的信号（CP-IDEM-06） | MUST |
| P13.5 | 检查顺序固定：参数校验 → 对 target 的授权与数据范围检查 → 幂等预查或认领 → 状态机校验 → 业务写。建类命令的重放结果要再过一遍组件自己的范围内读取 | MUST |
| P13.6 | 并发的同键请求只执行一次，后到的拿到重放结果或 `IN_PROGRESS`（CP-IDEM-07） | MUST |
| P13.7 | 键在 30 天内有效（E5，写进契约），存在 `besdk_idempotency` 表里（附录 A），由 SDK 清理 | MUST |
| P13.8 | 事件 handler 里调别人的写命令，用从事件派生出的确定性键（如 `crm-won:<opportunity_id>`），落在 `svc:` 命名空间 | MUST |

### P14 后台工作

| 种类 | 语义 | 表 |
|---|---|---|
| `Every` | 每个副本都跑；靠 `SKIP LOCKED` 认领工作，副本之间天然竞争 | — |
| `Singleton` | 全局同一时刻只有一个在跑。租约 TTL 30 s，每过 TTL/3 续约；丢了租约就取消这次运行；`epoch` 作为防护令牌 | `besdk_job_lease` |
| `Cron` | 每个时间槽全局只跑一次。用 `INSERT … ON CONFLICT DO NOTHING` 抢槽，不需要领导者。错过的槽只补跑最近一个。时区默认 `BUSINESS_TIMEZONE` | `besdk_job_slot` |
| `Queue` | 在业务事务里入队，至少执行一次。认领用 `SKIP LOCKED`；按退避重试；重试用尽进 `dead` 状态，并调用 `OnDead`；可选的 `unique_key` 保证同一个键只入队一次 | `besdk_job_queue` |
| `Reconciler` | 按"非终态且已过期"扫描候选；逐行原子认领、带租约；`Handle` 在事务外执行，`Apply` 在短事务里推进；退避；超过上限调用 `GiveUp`（挂起 + 开异常待办） | `besdk_reconcile` |

| # | 规则 | 等级 |
|---|---|---|
| P14.1 | 组件里所有不由请求触发的工作，都必须登记成上面五种之一。模块代码里不许自己写 ticker 循环（门禁 `module-ticker-scan`） | MUST（INTERNAL） |
| P14.2 | 监督见 P1.7。每次运行有超时，超时就取消（CP-JOBS-01…05：两个副本同一个 Cron 槽只跑一次；Singleton 同一时刻只有一个；Queue 每个作业只执行一次；业务事务回滚则作业不存在；任务失败后被重启） | MUST |
| P14.3 | 指标：`be_job_runs_total{job,result}`、`be_job_duration_seconds`、`be_job_last_success_timestamp_seconds`、`be_queue_depth{kind,state}`、`be_queue_oldest_age_seconds`、`be_reconcile_pending{name}`、`be_reconcile_oldest_age_seconds`、`be_reconcile_giveups_total` | MUST |
| P14.4 | 只读的运维端点 `GET /{d}/{n}/_ops/jobs`，权限键 `<domain>.<name>.ops`，由 be-ops 自动登记 | SHOULD |

### P15 快照（别人数据的本地副本）

| # | 规则 | 等级 |
|---|---|---|
| P15.1 | 快照行带上游的聚合版本。事件、读穿透、回填三条写入路径共用一个 Upsert，带 `WHERE 本地.version < 传入.version`；版本相等就什么都不做 | MUST |
| P15.2 | 字段不全的事件只更新已有行，不新建行。新建只来自完整状态：完整事件、BatchGet、List | MUST |
| P15.3 | 能读穿透的地方就读穿透（缺行，或比 `StaleAfter` 旧，就 BatchGet，写回，再返回）。只有枢纽的热路径、或者需要全量的视图，才在启动时回填：翻上游的 `List`，进度记在 `besdk_snapshot_sync`，可续跑，先订阅、后回填。上游缺席时把缺失的 ID 交给调用方：安全相关的（额度）fail-closed，展示相关的（名字）降级 | MUST |
| P15.4 | 没人读的快照删掉（E6） | MUST（组件义务） |

### P16 数据生命周期

| # | 规则 | 等级 |
|---|---|---|
| P16.1 | 每个有库的组件提供 `migrations/lifecycle.yaml` v1，字段全集见 data-lifecycle-v2 §4.3。迁移里出现的每一张表都要声明；`ledger` 类不许有 `pii` 列；声明了 `cold` 的表，`NUMERIC` 列都要带精度（门禁 `lifecycle-scan`） | MUST |
| P16.2 | 引擎作为 Singleton 运行；每一步一个事务，加一把步骤锁（P10.8），设 `lock_timeout`；DETACH 和 DROP 走专用的维护连接，并用 `CONCURRENTLY`。必须守住 data-lifecycle-v2 §4.5 的 G1–G12 | MUST（INTERNAL，由 `lifecycleconf` 测） |
| P16.3 | 读一个时间范围：要么拿到完整结果，要么答 `RANGE_COLD`，并在 `metadata` 里给出冷区间、能否解冻、能否异步导出。不静默截断。List 请求有可选字段 `include_cold`（CP-LIFE-02） | MUST |
| P16.4 | 资源契约 `/{d}/{n}/_lifecycle/*`（OpenAPI 片段和 gRPC `be.lifecycle.v1` 都在 be-protocol 里），端点全部挂出；还没实现的答 501 `CAPABILITY_UNAVAILABLE`（CP-LIFE-03） | MUST |
| P16.5 | 封存单元不可改：UPDATE / DELETE / TRUNCATE 被拒，映射成 `FAILED_PRECONDITION` + `UNIT_SEALED` | MUST |
| P16.6 | 迁移跑完的当天就能写入：分区窗口由平台迁移建好（CP-LIFE-01：在新库上迁移后立刻写一条 outbox） | MUST |

### P17 对象存储

| # | 规则 | 等级 |
|---|---|---|
| P17.1 | 走 S3 API。每个组件一个 bucket、一套凭据，策略只允许访问自己的 bucket（foundations-data-platform §8.2） | MUST |
| P17.2 | 大文件不进 gRPC 或 REST 的响应体，返回预签名 URL（有效期 ≤ 5 min）或附件 ID。bucket 永不公开读 | MUST |

### P18 可观测性

**P18.1 trace**：W3C TraceContext + Baggage。HTTP 和 gRPC 的入站提取、出站注入；事件把 `traceparent` 写进信封，消费端开一个新的 span，用 **span link** 指向生产者，不作为它的子 span。resource 属性：`service.name` 是组件 ID，`service.version`、`service.namespace` 是项目名，`service.instance.id`，`deployment.environment`。外壳里**每个成员一个 TracerProvider**（CP-OBS-01…03：HTTP → gRPC → outbox 事件 → 消费，是同一个 trace_id 或者有一条 link）。

**P18.2 日志**：stdout，一行一个 JSON 对象，最长 2 KiB（超出截断并标 `…[TRUNCATED]`）。

| 字段 | 何时出现 | 说明 |
|---|---|---|
| `time` | 总是 | RFC 3339，纳秒，UTC |
| `level` | 总是 | `debug` / `info` / `warn` / `error` |
| `msg` | 总是 | 事件名或一句话 |
| `component_id` `component_version` | 总是 | 外壳里取成员自己的值 |
| `trace_id` `span_id` | 有 span 时 | 访问日志**必须**有 |
| `request_id` | 请求内 | — |
| `sub` | 已验签时 | 不放 token |
| `act` | 有代理链时 | JSON 形式 |
| `caller` | 系统面 | `be-caller` |
| `perm` | 受保护路由 | 本次判定的键 |
| `event_id` `subject` `delivery` | 事件 handler 里 | — |
| `job` | Job 里 | — |
| `error` `error.code` `error.reason` | 出错时 | `error` 是脱敏后的错误文本 |
| `http.request.method` `http.route` `http.response.status_code` `duration_ms` | 访问日志 | 属性名按 OTel 语义约定 |
| `rpc.service` `rpc.method` `rpc.grpc.status_code` | gRPC 日志 | 同上 |

PII 键自动脱敏：`phone`、`mobile`、`id_card`、`password`、`bank_card`、`email`、`token`、`secret` → `[REDACTED]`。三门语言都在 handler 里自动做，不靠业务代码去调。

**P18.3 指标**：Prometheus 文本格式，在主端口的 `/metrics` 上。每个序列都带 `component` 标签；外壳里汇总所有成员的指标，同样带这个标签（V-08）。

| 名字 | 类型 | 标签 |
|---|---|---|
| `be_http_server_requests_total` | counter | `method` `route`（模板，不是原始路径）`status_code`（数字） |
| `be_http_server_duration_seconds` | histogram | `method` `route` |
| `be_grpc_server_handled_total` / `_duration_seconds` | counter / histogram | `service` `method` `code` |
| `be_grpc_client_handled_total` / `_duration_seconds` | counter / histogram | `target` `method` `code` |
| `be_outbound_inflight` | gauge | `target` |
| `be_db_pool_in_use` / `be_db_pool_wait_seconds` | gauge / histogram | — |
| `be_tx_retries_total` | counter | `reason` |
| `be_db_identity_ok` | gauge | — |
| `be_outbox_pending` / `be_outbox_oldest_age_seconds` | gauge | — |
| `be_events_published_total` | counter | `subject` |
| `be_consumer_handled_total` | counter | `subject` `result`（`applied` / `skipped` / `nak` / `dlq`） |
| `be_consumer_lag_seconds` | gauge | `subject` |
| `be_dlq_messages_total` | counter | `subject` |
| `be_authz_bundle_age_seconds` / `be_authz_projection_lag` | gauge | — |
| `be_authz_denied_total` | counter | `reason` |
| `be_cache_hits_total` / `be_cache_misses_total` / `be_cache_evictions_total` / `be_cache_entries` | counter / gauge | `name` |
| Jobs 一组 | — | 见 P14.3 |
| 生命周期一组（`be_lifecycle_blocked{table,reason}` 等） | — | 见 data-lifecycle-v2 §4.4 |

### P19 外壳合并的义务

| # | 规则 | 等级 |
|---|---|---|
| P19.1 | 一个外壳只装**同一门语言、同一个 SDK 版本**的成员，成员编译或链接进外壳镜像。启动时读 `BRICKKIT_SERVED_MEMBERS_CONFIG`：出现没编译进来的成员，或者成员版本和编译进来的版本不同（Go 读 build info，Python 读 `importlib.metadata`，TS 读成员包的 `package.json`），就以非 0 退出，并点名是哪个成员（CP-SHELL-01、02） | MUST |
| P19.2 | 每个成员用它自己那一项的 `config`、`httpPort` 和 `extraPorts`；成员之间互相调用仍然走网络（0101、0108） | MUST |
| P19.3 | 整个进程只有四样东西是共享的：OTel 导出器和传播器；JWKS 验签器和 bundle；DB 物理池；总线连接。共享的前提是各成员的 `AUTHZ_URL`、`IAM_*`、`TENANT_ID`、`PG_HOST` / `PG_PORT` / `PG_DATABASE`、`EVENT_BUS_URL` 都和外壳自己的一致；任何一项不一致都拒绝启动（修"静默忽略成员的 PG_HOST"）（CP-SHELL-03） | MUST |
| P19.4 | 其余的一切按成员实例化：Logger、Prometheus Registry、TracerProvider 和 MeterProvider（`service.name` 是成员 ID）、`Store`（成员的身份 + 成员的连接预算）、gRPC 连接池和出站舱壁、durable、Jobs、缓存、ACL 投影、生命周期引擎（CP-SHELL-04、05） | MUST |
| P19.5 | 外壳的登录角色是 NOINHERIT 的，只通过 `SET LOCAL ROLE` 进入成员角色（PG16 `GRANT … WITH INHERIT FALSE, SET TRUE`） | MUST |
| P19.6 | 外壳的 `/healthz` 只答外壳进程本身。成员初始化失败，整个外壳就启动失败；成员运行中的后台任务失败，由监督重启，不永久停止（CP-SHELL-06） | MUST |
| P19.7 | 外壳在自己的端口上暴露汇总的 `/metrics`；每个成员的 `/metrics` 也照常可用 | MUST |

### P20 自描述与协议版本

`GET /_be/info`（主端口，不进边缘、不鉴权，内容不含密钥）：

```json
{
  "component_id": "erp/sales", "component_version": "3.0.0",
  "protocol": "1.0",
  "sdk": { "name": "be-sdk-go", "version": "0.6.0" },
  "language": { "name": "go", "version": "1.25.11" },
  "profiles": ["core", "auth", "scope", "grpc", "outbound", "events-pub", "events-sub", "idempotency", "db", "jobs", "lifecycle"],
  "ports": { "http": 8085, "grpc": 9095 },
  "migrations": { "component": "0007", "platform": 3 },
  "members": null
}
```

外壳上 `members` 是成员信息的数组，每一项也是这个形状，只是没有 `members` 字段。compconf 先读它，再核对容器和声明是否一致（CP-CORE-11）。

| # | 规则 | 等级 |
|---|---|---|
| P20.1 | 协议版本写成 `MAJOR.MINOR`。minor 只加**可选**的面：新的能力位、新的可选端点、新的可选字段，而且不改 1.0 已有面的含义。必须做到的新行为只能出现在 major 里 | — |
| P20.2 | 组件在 `assembly.yaml` 里声明 `protocol: "1.0"`，表示按 1.0 的用例集来测。be-acceptance 给每个 minor 保留一份用例集，旧组件永远按它声明的那个版本来测 | MUST |
| P20.3 | SDK 在 `/_be/info` 和 README 里写明它实现的协议版本 | MUST |

---

## 3. 规范放在哪、怎么版本化

### 3.1 仓库 `brickKit/be-protocol`（新建，需用户同意，§9 Q1）

```
be-protocol/
  README.md  README.zh.md        是什么、怎么读、版本规则
  CHANGELOG.md
  spec/en/P01-lifecycle.md … P20-self-description.md   正文，英文为准
  spec/zh/…                                           中文镜像，同样的 ## 小节
  schemas/  config-keys.yaml       协议级配置键：名字、类型、是否密钥、默认值、属于哪个 profile（P2）
            errors-be.yaml         SDK 保留的 reason（P4）
            problem.schema.json    problem+json 的 JSON Schema
            envelope.schema.json   CloudEvents 头 + 扩展属性（P12）
            lifecycle.schema.json  lifecycle.yaml v1（data-lifecycle-v2 §4.3）
            errors-yaml.schema.json   组件 contracts/errors.yaml 的格式
            assembly-protocol.schema.json   assembly.yaml 里本协议用到的键：protocol、conformance、resources、requires_capabilities
            info.schema.json       /_be/info
            fixtures.schema.json   组件 conformance/fixtures.yaml 的格式（§4.3）
            compconf-report.schema.json
  proto/be/v1/limits.proto         extend FieldOptions { int32 max_items = 51001; }
        be/lifecycle/v1/lifecycle.proto
  openapi/  resource-authz.yaml (_authz/check|explain, _shares)
            resource-lifecycle.yaml (_lifecycle/*)
            ops.yaml (/healthz /readyz /_be/info /_ops/jobs)
  sql/platform/*.sql               平台表参考 DDL（附录 A）。规范性的，SDK 自己的平台迁移必须产出同样的表结构
  vectors/  authz/ money/ idempotency/ envelope/ calendar/ numbering/ lifecycle/ search/ errors/ config/ redaction/
            SHA256SUMS
  fixtures/widget/                 夹具组件的契约与行为说明（apis 文件 §6）
  fs.go  go.mod                    唯一的代码：//go:embed 把 schemas、vectors、sql 导出成 fs.FS，供 be-acceptance 和 be-sdk-go 的测试用
```

为什么单独成仓库，而不是放进 be-acceptance 或某个 SDK：

- **规范不属于任何一门语言**。放进 be-sdk-go，就又回到"Go 才是标准答案"。
- **规范和语义向量必须用同一个版本号**。三门 SDK 和 compconf 都钉同一个 tag。
- 和 `contract-infra-authz`、`contract-infra-iam` 同一个套路：契约仓库只放契约，实现和测试放别处。这个模式也写进 brickKit 候选（§8 B9）。

### 3.2 版本规则

- tag 写成 `v1.0.0`。带 `v` 是因为 be-acceptance 和 be-sdk-go 把它当 Go module 引用。
- **patch**：措辞澄清、补向量，不改任何语义。
- **minor**：只加可选的面（P20.1）。
- **major**：会让已经符合的组件变得不符合的改动。
- 变更顺序固定，**不允许 SDK 里出现规范没写的行为**：
  1. 在 be-protocol 改正文和 schema；
  2. 补向量；
  3. be-acceptance 加 compconf 用例，先对坏夹具跑出红（§4.7）；
  4. 三门 SDK 并行实现，各自的 widget 都跑绿；
  5. 打 tag。
- 谁钉谁：
  - be-acceptance 精确钉一个 be-protocol 版本；
  - be-sdk-go 在测试里 import 它；
  - be-sdk-python、be-sdk-ts 用 `make sync-vectors` 从 tag 拷贝 `vectors/` 和 `schemas/`，并核对 `SHA256SUMS`。这是拷测试数据，不是拷代码，0101 不受影响。
- 族契约（authz、iam）独立版本化。be-protocol 的正文只引用它们的 major，例如"`contract: authz/2.x`"。授权相关向量里的 bundle 样例，标明取自 `contract-infra-authz` 的哪一个版本。

### 3.3 正式文档怎么指向它

- `docs/{en,zh}/04-foundations/` 新增一篇 `02-languages-and-component-protocol.md`（第二波，计划中；编号已由 foundations README 定好）。按 foundations 的 11 个固定小节写：
  - Choice：协议加黑盒套件，SDK 是参考实现。
  - Alternatives：
    - 锁死语言（即今天的 0105）；
    - sidecar（Dapr）：外壳里只能有一个 app-id，成员身份丢失；
    - WASM 组件模型：生态不成熟，PG / gRPC 驱动缺；
    - 每门语言各自约定、不做黑盒测试：漂移无法发现。
  - When to switch：出现必须跨语言合进一个进程的需求，这一条永远不支持，写成 Known limits。
  - 仓库建好之前，正式文档只写名字 `brickKit/be-protocol` 并标"计划中"，**不放链接**（不存在的地址不链）；建好之后再链到它的 GitHub 地址（外部链接不受 `docs-boundary` 约束）。
- `01-conventions/02-backend.md` 重写成"用官方 SDK 写组件"：每一节"怎么做"都指向对应的 P 章节。新增一节"用其它语言写组件"（§5.6）。
- 根 `AGENTS.md` 的约定表加一行 **Component protocol**；Where to look 表加一行"用别的语言写组件 / 组件协议 / compconf"；Pitfalls 表按 §7.6 的清单增删。
- 组件 BRICKKIT 的 "Before you deploy" 写通用的运行要求（库身份一句话见 data-layer §2.2）。非官方 SDK 的组件，额外写明内存与冷启动的量级。

---

## 4. 黑盒一致性套件 `compconf`

### 4.1 目标与边界

- **测什么**：§2 里每一条 MUST 规则中可以从外面观察到的部分。
- **怎么测**：只对镜像和它暴露的端口、它写的库表、它发的消息、它的日志和指标下判断，**不读源码**。所以 Go、Python、TS 和第四门语言用的是同一个判定标准。
- **不测什么**：INTERNAL 规则，例如事务里禁止网络调用、嵌套事务、谓词的 SQL 形状、决策不跨请求缓存。这些由官方 SDK 自己的测试守住，第四门语言的组件由评审核对。
- **附带收获**：compconf 本身就是协议正确性的回归测试。三门 SDK 的 widget 过同一套用例，就是"三门 SDK 等价"的证据。

### 4.2 架构

```
tools/be-acceptance/conformance/component  (compconf；Go，跑在一个容器里，和被测容器在同一个 docker 网络)
 ├─ 读入：component.yaml、assembly.yaml、contracts/（openapi、proto、events、errors.yaml）、
 │        migrations/lifecycle.yaml、conformance/fixtures.yaml、镜像引用
 ├─ 基础设施（真的）：
 │    PG：make up 的实例，库 brickkit_test_db；每次运行现建随机 schema + 随机 LOGIN 角色（只授 USAGE+CREATE）
 │        + 一个 NOINHERIT 的"外壳"角色；跑完全部删掉（同 besdktest）
 │    NATS：每次运行起一个一次性的 nats-server -js 容器，流和 durable 不和开发环境相撞
 ├─ 假服务（套件进程内）：
 │    fake-iam    JWKS + 签发器：签 access / refresh / 错 iss / 错 aud / 无 exp / HS256 / 轮换后的钥匙 …
 │    fake-authz  contract-infra-authz v2：bundle（每条用例脚本化）、changes、ReadTuples、Check、WriteTuples、poke
 │    fake-peer   被测组件的每个依赖：从依赖的 proto 描述符动态应答（protoreflect）；
 │                记录 metadata、截止时间、连接数；可以挂起、返回 UNAVAILABLE、变慢
 │    otlp-sink   OTLP/HTTP 接收器，按 trace_id 收 span
 └─ 被测容器：先 migrate（两次），再 serve（1 个或 2 个副本）；外壳模式下按 BRICKKIT_SERVED_MEMBERS_CONFIG 起
```

套件给被测容器的配置：

- 先取 `configSchema` 的默认值；
- 再盖上套件的值：随机的 PG 身份、`AUTHZ_URL` / `IAM_*` / `TENANT_ID` 指向假服务、依赖的 `*_ENDPOINT` 指向 fake-peer、`OTEL_BASE_URL` 指向 otlp-sink；
- 再盖上加速用的键：`EVENTS_BACKOFF=200ms,500ms,1s`、`EVENTS_MAX_DELIVER=3`、`GRPC_MAX_CONNECTION_AGE=10s`、`JOBS_OVERRIDES`。

所以协议级配置键（P2）同时也是**可测性接口**：套件不需要任何"测试模式"开关，只调运维本来就能调的键。

### 4.3 组件怎么加入

`assembly.yaml`（本项目自己的键，brickKit 不读）：

```yaml
protocol: "1.0"
conformance:
  fixtures: conformance/fixtures.yaml
  skip:                                   # 只能跳过可选用例，必须写理由；必测用例不能跳
    - { case: CP-OUT-04, reason: "没有幂等的出站方法" }
```

profile 由清单里的事实**自动选**，组件不用声明：

| profile | 什么时候启用 | 用例数（约） |
|---|---|---|
| `core` | 一律 | 11 |
| `obs` | 一律 | 5 |
| `err` | 一律 | 4 |
| `auth` | 有任何非 Public 路由 | 13 |
| `scope` | `data_scopes` 不是 `none`，或声明了 `resources` | 15 |
| `grpc` | 有名为 `grpc` 的 extraPort | 6 |
| `outbound` | `dependencies.components` 非空 | 8 |
| `events-pub` | `contracts/events` 里有本组件发布的 subject | 5 |
| `events-sub` | 订阅了任何 subject（fixtures 里列出） | 7 |
| `idempotency` | 任何写操作带 `idempotency_key` / `Idempotency-Key` | 8 |
| `db` | `configSchema` 里有 `PG_SCHEMA` | 4 |
| `jobs` | 有库（平台任务一定存在） | 5 |
| `lifecycle` | 有库 | 4 |
| `blob` | `configSchema` 里有 `S3_BUCKET` | 3 |
| `shell` | `component.yaml` 有 `shell.members` | 8，外加对每个成员在外壳模式下重跑它的 profile |

`conformance/fixtures.yaml` 告诉套件"怎样让这个组件做事、怎样看到结果"。它是数据，不是代码；第四门语言也写同一份。以 erp/sales 为例（节选）：

```yaml
users:
  rep_east:  { roles: [dev_sales_rep], dept_path: /1/3/, legal_entity: LE01 }
  rep_west:  { roles: [dev_sales_rep], dept_path: /1/7/ }
  no_dept:   { roles: [dev_sales_rep], dept_path: "" }
grants:                                       # 进 fake-authz 的 bundle；scope profile 会在此基础上做随机组合
  dev_sales_rep: { keys: [erp.sales.view, erp.sales.create, erp.sales.confirm], levels: { erp.sales.view: subtree } }
resources:
  erp.sales.order:
    create:  { method: POST, path: /erp/sales/orders, as: rep_east, body_file: order-create.json, id: $.id }
    get:     { method: GET,  path: "/erp/sales/orders/{id}" }
    list:    { method: GET,  path: /erp/sales/orders }
    command: { method: POST, path: "/erp/sales/orders/{id}/confirm", key: erp.sales.confirm, idempotent: true,
               two_phase: true, triggers: { grpc: "erp.inventory.v1.InventoryService/Reserve" } }
dependencies:
  erp/inventory:
    "erp.inventory.v1.InventoryService/Reserve": { response_file: reserve-ok.json }
events:
  produces:  { via: resources.erp.sales.order.command, subject: sales.order.created.v1 }
  consumes:
    - subject: mdm.customer.updated.v1
      sample_file: customer-updated.json          # 套件改 ce-aggregateversion，造出乱序和重复
      observe:  { sql: "SELECT version, credit_limit FROM customer_snapshots WHERE customer_id = $1" }
```

`observe.sql` 读的是被测组件**自己 schema 里的表**。套件拥有这个库，所以能直接查，这不算偷看代码。没有公开读接口的消费效果（快照、台账）就靠它观察。

### 4.4 用例目录（代表性用例，ID 稳定，只增不改）

| profile | 用例 |
|---|---|
| core | 01 迁移连跑两次都是 0 退出；02 缺必填键或类型错 → 退出码 78，日志点名键；03 PG / NATS / authz 晚于组件就绪 → 组件不退出，依赖就绪后恢复；04 停掉 PG 后 `/healthz` 仍是 200；05 `/readyz` 语义（SHOULD）；06 SIGTERM → 在途请求完成、在宽限期内以 0 退出；07 镜像里有 sh 和 wget；08 慢速请求头被断开；09 超过请求体上限 → 413；10 `X-Request-Id` 回写，缺失时生成；11 `/_be/info` 与清单一致 |
| obs | 01 入站带 `traceparent` → otlp-sink 看到的 span 以它为父；02 日志字段齐全，访问日志带 `trace_id`；03 `/metrics` 的名字、`component` 标签、`route` 是模板；04 PII 键被脱敏；05 `LOG_LEVEL=warn` 时没有 info 行 |
| err | 01 每个 4xx 都是 problem+json，`reason` 在 errors.yaml 或 errors-be.yaml 里；02 gRPC 错误带 ErrorInfo，并能与 REST 互相还原；03 运行中套件收回某张表的权限 → 500 只有通用文案 + `trace_id`，响应里没有 SQL 原文；04 出现过的每个 reason 都登记过 |
| auth | 01 没有 token → 401；02 `alg: none` / HS256 / 没有 kid → 401；03 刷新令牌 → 401；04 iss 不对；05 aud 不对；06 没有 exp；07 JWKS 轮换、不认识的 kid 触发刷新；08 stale → 401 `token_stale`；09 openapi 里的每个操作都有守卫，不带 token 时非 Public 的一律 401；10 还没拿到 bundle → 503 `AUTHZ_NOT_READY`；11 缺键 → 403 `MISSING_PERMISSION`；12 `act.kind=agent` → 401 `UNSUPPORTED_DELEGATION`；13 拿到 bundle 后停掉 authz → 照常判定（fail-static） |
| scope | 01 own / dept / subtree / all 四档矩阵；02 按键求值；03 维度取值和 `*`；04 `until` 到期；05 多个角色取最高档；06 R60：没有部门的人只看到自己的；07 看不见的单条读 → 404；08 对看不见的记录发命令 → 404；09 看得见做不了 → 403，维度参数越权 → 403 `OUT_OF_SCOPE`；10 **List/Can 一致**（随机授权组合的属性测试，比对列表和 `_authz/check`）；11 字段掩码、按掩码字段排序被拒；12 `_authz/check` 的形状和上限；13 explain 不泄露看不见的记录；14 `sharing=false` 时 `_shares` 答 501；15 changes 下发共享 → 6 s 内可见，带 `X-Authz-Revision` 时立刻可见，撤销后不可见 |
| grpc | 01 没有 `be-caller` → `UNAUTHENTICATED`；02 系统调用的日志带 `caller`；03 面向用户的方法经 gRPC → `UNAUTHENTICATED`；04 5 MiB 请求被拒；05 `MaxConnectionAge` 之后发 GOAWAY，客户端透明重连；06 BatchGet 超上限 → `BATCH_TOO_LARGE` 加 BadRequest |
| outbound | 01 触发 50 次 → fake-peer 只看到 1 条连接；02 出站的 `grpc-timeout` ≤ 3 s，且小于入站剩余；03 只对幂等方法在 UNAVAILABLE 时重试；04 一直 UNAVAILABLE 时，重试量 ≤ 10 %；05 对端挂起、并发超过 64 → 立刻 `OUTBOUND_LIMIT`；06 `UserHTTP` 转发 Authorization、`x-request-id`、`traceparent`；07 对端挂起 → 组件在路由截止时间内答 504，不跟着挂死；08 出站带 `be-caller`、`be-actor-sub`、`traceparent` |
| events-pub | 01 命令 → 流上出现事件，`ce-*` 头齐全，`ce-id` 是 UUIDv7 且等于 `Nats-Msg-Id`，`aggregatetype` 与契约一致，`traceparent` 和请求同一个 trace；02 停掉总线 → 命令照样成功 → 恢复总线 → 恰好送达一次；03 两个副本 → 每行 outbox 只发布一次；04 没有流就按默认值建，已有的流配置不被覆盖；05 payload 通过契约校验，超过上限明确报错 |
| events-sub | 01 durable 的名字和参数；离线期间发布的事件，上线后补收；02 重复投递只生效一次；03 乱序（v3 先于 v2）的最终状态与按序相同（属性测试）；04 格式错误的 payload → DLQ，带 `be-dlq-*` 头；05 临时失败（套件暂时收回表权限）→ Nak 重投 → 恢复后生效；06 handler 里发出的事件带 `causationid` 且 `hopcount` + 1，`hopcount=11` 的入站事件进 DLQ；07 交易单据事件缺法人 → DLQ |
| idempotency | 01 重放返回首次结果；02 换请求体 → 400 `IDEMPOTENCY_MISMATCH`；03 换 target；04 换命令；05 两段式命令进行中 → 409 `IDEMPOTENCY_IN_PROGRESS`；06 不同 caller 同一个键互相独立；07 并发同键只执行一次；08 请求头和 body 等价，冲突时 400 |
| db | 01 随机身份下全部 profile 照常通过，表的属主全是 `PG_USER`，schema 外没有任何对象；02 套件持锁 → 组件在 `lock_timeout` 内答 409 `LOCK_TIMEOUT`；03 压满并发 → 该角色的连接数 ≤ `PG_POOL_MAX`；04 `besdk_*` 表与参考 DDL 逐列一致（查目录比对） |
| jobs | 01 两个副本，平台 Cron（`be.cleanup`，用 `JOBS_OVERRIDES` 改成每 2 s）每个槽只跑一次；02 Singleton（生命周期引擎）同一时刻只有一个持有者，杀掉持有者后另一个在 TTL 内接管；03 Queue 的作业在两个副本下只执行一次（fixtures 给出会入队的命令）；04 业务事务回滚 → 作业不存在；05 运行中 `pg_terminate_backend` → 任务失败后被重启，进程不退出 |
| lifecycle | 01 新库迁移后立刻能写入（分区窗口已就绪）；02 早于在线下界的范围 → `RANGE_COLD`；03 `_lifecycle/*` 都已挂出，未实现的答 501；04 `lifecycle.yaml` 通过 schema 校验，覆盖了全部表 |
| blob | 01 预签名 PUT 带内容长度上限；02 bucket 不可匿名读；03 预签名有效期 ≤ 5 min |
| shell | 01 出现没编译进来的成员 → 非 0 退出并点名；02 成员版本不符 → 非 0 退出；03 成员的 `PG_HOST` 或 `AUTHZ_URL` 与外壳不同 → 拒绝启动；04 每个成员的 span，`service.name` 是成员 ID；汇总的 `/metrics` 带 `component` 标签；05 一个成员把连接预算耗尽，另一个照常；两个成员订阅同一个 subject 各收一份；06 成员的后台任务失败后被重启；07 NOINHERIT 的登录角色下，四类后台路径全部正常；08 对每个成员按外壳模式重跑它自己的 profile |

### 4.5 报告

- 机器可读的报告是 `compconf-report.json`，结构由 `schemas/compconf-report.schema.json` 定义：

  ```json
  {"suite":"be-acceptance@0.6.0","protocol":"1.0","component":"erp/sales","version":"3.0.0",
   "image":{"ref":"erp-sales:3.0.0","digest":"sha256:…"},"sdk":{"name":"be-sdk-go","version":"0.6.0"},
   "env":{"postgres":"16.4","nats":"2.10.x"},
   "profiles":{"core":{"status":"pass","cases":[{"id":"CP-CORE-01","status":"pass","ms":812}]}, "…":{}},
   "skipped":[{"case":"CP-OUT-04","reason":"…"}]}
  ```
- 人读的版本是 Markdown，写进 `dev/test-records/<阶段>/compconf/<repo>@<version>.md`，旁边放那份 JSON。
- 退出码：任何一条 MUST 失败，就非 0。SHOULD 失败只记警告。

### 4.6 和 `make gates`、发版流程怎么接

- `make conformance ID=<组件> [SHELL=<外壳>]`：本地跑一遍（几分钟级），产出报告。
- 门禁 **`compconf-record-scan`**，进 `make gates`。它是离线的、很快：
  - `brickkit.yaml` 里的每个组件和外壳，都要有对应**精确版本**的报告；
  - 报告里的镜像摘要等于本地镜像（本地没有镜像时只警告）；
  - 套件版本不低于 be-acceptance 要求的最低版本；
  - 必测 profile 全部 pass，skip 都有理由。
- `version-bump-ship` 技能在"构建镜像"之后、"打 tag"之前加一步：跑 compconf，把报告和组件指针一起提交。镜像变了，就必须重跑。
- 第四门语言的组件，走完全相同的路径。

### 4.7 先见红，才信绿

- 每门 SDK 的 widget 都有几个**故意写坏的变体**（构建参数切换），每个只违反一条规则：
  - 收刷新令牌；
  - `/healthz` 查库；
  - 不带 `ce-id`；
  - 用 `SELECT` 认领 outbox；
  - 不切角色直接写；
  - 池没有上限。
- 套件自检 `make compconf-selftest` 断言：每个坏变体都恰好在对应的用例上失败。
- 这对应 06-testing 的"新门禁先见一次红"。

### 4.8 与其它一致性套件的分工

| 套件 | 测什么 | 对谁跑 | 谁必须过 |
|---|---|---|---|
| `be-protocol/vectors`（不在任何套件里） | 纯语义：授权求值、money、幂等指纹（JCS）、信封派生（causationid、hopcount）、法人日历、编号格式、生命周期 Planner、搜索规范化、错误映射、配置解析 | 每门 SDK 的单元测试（离线） | 每门官方 SDK；第四门语言 SHOULD |
| **compconf** | 组件协议里可观察的部分 | 运行中的组件或外壳容器 | **每个组件、每个外壳** |
| `authzconf` | authz 族契约（provider 黑盒 + 用 widget 做的端到端，authz-architecture §5.4） | authz 成员 | infra/authz、authz-static、authz-openfga |
| `iamconf` | IAM 族契约（foundations-data-platform §11.3） | iam 成员 | iam-casdoor、iam-keycloak、iam-oidc |
| `busconf` | Broker 端口（foundations-communication §6.4） | 每门 SDK × 每个适配器，经 widget | jetstream、pgqueue |
| `dbconf` | 数据库引擎的能力 | 引擎 | PG 14 / 16 / 17；信创库按触发条件 |
| `lifecycleconf` | 生命周期引擎和冷层适配器（data-lifecycle-v2 §5.3） | 每门 SDK × 每个适配器，经 widget | — |
| `blobconf` / `secretconf` / `searchconf` | 对应的端口 | 适配器 | — |

全部放在 `tools/be-acceptance/conformance/<端口短名>/`：`component`、`authz`、`iam`、`bus`、`db`、`lifecycle`、`blob`、`secret`、`search` 等；上表的 `…conf` 只是非正式简称。总线和生命周期的适配器住在每门 SDK 里，所以 `busconf` 和 `lifecycleconf` 要"每门 SDK 各跑一遍"。Python 的冷层适配器是可选安装的 `besdk[cold]`，没装时，SDK 在加载声明的那一刻就报"不支持"（data-lifecycle-v2 §4.14），套件把这断言为"明确降级"。

---

## 5. 官方 SDK：参考实现（概览；逐个 API 见 `sdk-redesign-apis.md`）

### 5.1 原则

1. **同形**：三门语言用同一组名词、同一组模块字段、同一组错误 reason。命名各按语言惯例（Go 用 PascalCase，Python 用 snake_case，TS 用 camelCase），但只是大小写不同，名词不变（§5.2）。AI 在一门语言里学会的写法，换一门语言照样能用。
2. **组件只看到协议，看不到基础设施**：
   - `rt.DB`、`rt.NATS` 不再对模块开放；
   - 适配器（jetstream / pgqueue、pgdialect、冷层）都在 SDK 内部，按 URL scheme 或配置值选用；
   - 组件不 import 任何适配器包（foundations-communication §2.4）。
3. **一个入口**：每一件事只有一种写法。
   - 事务：`Store.Tx`；
   - 发事件：`tx.Publish`；
   - 异步命令：`tx.Enqueue`；
   - 后台工作：模块的 `Jobs` / `Workers` / `Reconcilers`；
   - 授权：`AccessFrom`；
   - 调别人：`Conn` / `UserHTTP` / `ExternalHTTP`。
4. **上下文**：Go 显式传 `ctx`；Python 用 `contextvars`；TS 用 `AsyncLocalStorage`。三者装的东西相同：截止时间、trace、request id、Access、事务标记、正在处理的事件（用来派生 causation 和 hop）。
5. **不做兼容层**（§1 第 1 条）。v0.5.0 的 API 在 v0.6.0 里整个换掉。
6. **每门 SDK 自带 `examples/widget`**，它同时就是"这门语言怎么写一个组件"的范例（AI 照着写），也是 compconf 的被测对象。

### 5.2 跨语言名词表（定名）

| 概念 | Go | Python | TS |
|---|---|---|---|
| 组件声明 | `besdk.Spec{ID, Migrations, Contracts, New}` | `besdk.Spec(id=, migrations=, contracts=, create=)` | `defineComponent({id, migrations, contracts, create})` |
| 进程入口（服务 + 迁移子命令） | `besdk.Main(spec)` | `besdk.main(spec)` | `main(spec)` |
| 模块 | `*besdk.Module` | `besdk.Module` | `Module` |
| 运行时 | `*besdk.Runtime`（只有方法，字段不导出） | `besdk.Runtime` | `Runtime` |
| 配置 | `rt.Config().Require("K")`、`.Int`、`.Duration`、`.Secret`、`.JSON` | `rt.config.require("K")` … | `rt.config.require("K")` … |
| 绑定身份的库句柄 | `rt.Store()` → `*besdk.Store` | `rt.store()` | `rt.store()` |
| 事务 | `store.Tx(ctx, fn)`、`store.TxWith(ctx, besdk.TxOptions{…}, fn)`、`store.ReadSnapshot(ctx, fn)` | `await store.tx(fn, isolation=…, …)`、`await store.read_snapshot(fn)` | `await store.tx(fn, {isolation, …})`、`await store.readSnapshot(fn)` |
| 事务对象 | `*besdk.Tx`（实现 sqlc 的 DBTX） | `besdk.Tx`（包着 asyncpg 连接） | `Tx`（包着 pg 的 client） |
| 事务内动作 | `tx.Publish(ctx, ev)`、`tx.Enqueue(ctx, kind, args, opts)`、`tx.Lock(ctx, name, parts…)`、`tx.NextNumber(ctx, series)`、`tx.SyncRelation(ctx, …)`、`tx.Seal(ctx, table, unit)` | `await tx.publish(ev)`、`await tx.enqueue(kind, args, …)`、`await tx.lock(name, *parts)`、`await tx.next_number(series)` … | `await tx.publish(ev)`、`await tx.enqueue(kind, args, opts)`、`await tx.lock(name, …parts)`、`await tx.nextNumber(series)` … |
| 命令幂等 | `besdk.Idempotent(ctx, tx, cmd, do)`；两段式用 `tx.IdemLookup` / `IdemClaim` / `IdemComplete` / `IdemRelease` | `await besdk.idempotent(tx, cmd, do)`；`tx.idem_*` | `await idempotent(tx, cmd, do)`；`tx.idem*` |
| 系统面 gRPC（取代 `SystemClient` / `UserClient`） | `rt.Conn(dep, "grpc")` → 缓存的 `*grpc.ClientConn` | `rt.conn(dep, "grpc")` → `grpc.aio.Channel` | `rt.conn(dep, "grpc")` → grpc-js `Channel`；`rt.client(Ctor, dep)` |
| 用户面 HTTP | `rt.UserHTTP(dep)` | `rt.user_http(dep)` | `rt.userHttp(dep)` |
| 第三方 HTTP | `rt.ExternalHTTP(name, opts)` | `rt.external_http(name, …)` | `rt.externalHttp(name, opts)` |
| 授权入口（取代 `ScopeOf` / `UserFrom` / `ScopeFrom`） | `besdk.AccessFrom(ctx)` → `*Access`：`.User()` `.Has(k)` `.Scope(t)` `.Can(k, r)` `.Mask(&v)` `.RowActions(…)` | `besdk.access()` | `access()` |
| 系统调用方 | `besdk.SystemFrom(ctx)`、`besdk.CallerOf(ctx)` | `besdk.system()`、`besdk.caller_of()` | `system()`、`callerOf()` |
| 路由注册 | `besdk.GET(r, path, guard, h, opts…)` | `@r.get(path, guard)` | `r.get(path, guard, handler, opts)` |
| 事件声明 | `besdk.Events{Publishes, Subscribe: []besdk.Subscription}` | `besdk.Events(publishes=, subscribe=)` | `{publishes, subscribe}` |
| 后台工作 | `besdk.Job`、`besdk.Worker`、`besdk.NewReconciler[T](spec)` | `besdk.Job`、`besdk.Worker`、`besdk.Reconciler` | `Job`、`Worker`、`reconciler(spec)` |
| 快照 | `besdk.NewSnapshot[T](spec)` | `besdk.Snapshot(…)` | `snapshot<T>(spec)` |
| 进程内缓存 | `besdk.NewCache[K, V](rt, name, opts)` | `besdk.Cache(rt, name, …)` | `cache<K, V>(rt, name, opts)` |
| 法人日历 | `rt.Calendar().Today(ctx, le)`、`.BusinessDate(ctx, le, t)`、`.FiscalPeriod(…)` | `rt.calendar.today(le)` … | `rt.calendar.today(le)` … |
| 标识 | `besdk.NewID()`、`besdk.IDTime(id)` | `besdk.new_id()`、`besdk.id_time(id)` | `newId()`、`idTime(id)` |
| 金额 | 包 `besdk/money` | `besdk.money` | `@brickkit/be-sdk-ts/money` |
| 对象存储 | `rt.Blob()` | `rt.blob()` | `rt.blob()` |
| 生命周期 | `rt.Lifecycle()`（引擎）；模块字段 `Lifecycle{Calendar, Guards, Checkpointers}` | 同形 | 同形 |
| 错误 | `besdk.Errorf(codes.X, "REASON", meta, fmt, …)`、`besdk.Permanent(err)` | `besdk.Error(code, reason, meta, msg)` | `beError(code, reason, meta, msg)` |
| 测试包 | `besdktest` | `besdk.testing`（pytest 插件） | `@brickkit/be-sdk-ts/testing` |
| 外壳启动器 | `shell.Main(shell.Members{…})` | `besdk.shell.main([…])` | `runShell([…])` |

`Module` 的字段（三门同名）：`HTTP`（注册用户面路由）、`GRPC`（注册系统面服务）、`Events`、`Jobs`、`Workers`、`Reconcilers`、`Snapshots`、`Sharing`（`MountSharing` 用的加载器）、`Lifecycle`（钩子）、`Start`（一次性初始化，有截止时间，**不许在里面起循环**）、`Stop`。

### 5.3 每门语言锁定的栈（0103 重写后的表）

| 层 | Go | Python | TypeScript |
|---|---|---|---|
| 运行时 | Go 1.25 | CPython 3.13（3.14 要实测 asyncpg 和 grpcio 的 wheel 再切） | **Node 24 LTS** |
| HTTP | Gin | FastAPI on uvicorn（一个进程、一个事件循环） | **Fastify 5**（BFF 的 GraphQL 用 graphql-yoga 5，挂在 Fastify 上） |
| gRPC | grpc-go | grpc.aio | **@grpc/grpc-js** + ts-proto 生成代码（`outputServices=grpc-js`） |
| 数据库 | database/sql + pgx/v5 stdlib，sqlc，手写 SQL | asyncpg，手写 SQL，Pydantic 映射行 | **pg（node-postgres）8**，手写 SQL，zod 校验行 |
| 迁移 | golang-migrate，纯 `.sql` | yoyo-migrations，纯 `.sql`（入口收进 SDK） | **node-pg-migrate**，纯 SQL 文件 |
| 事件 | nats.go `jetstream` | nats-py JetStream | **@nats-io/jetstream** + transport-node |
| 十进制 | cockroachdb/apd/v3 | 标准库 `decimal` | decimal.js |
| JWT | golang-jwt/v5 + keyfunc/v3 | PyJWT（必须传 `audience`） | jose 6 |
| 出站 HTTP | net/http | httpx | undici（按依赖一个 Agent） |
| 日志 / 指标 | slog / client_golang，每个模块一个 registry | logging（SDK 的 JSON formatter）/ prometheus-client，每个模块一个 CollectorRegistry | pino / 保留现用的 Prometheus 客户端，每个模块一个 Registry |
| trace | otel-go + otelgrpc | opentelemetry-python + grpc 拦截器 | @opentelemetry/sdk-trace-base；**不用 auto-instrumentation**（它全局打补丁，会破坏"每个成员一个 provider"） |
| 对象存储 | aws-sdk-go-v2 | aioboto3 | @aws-sdk/client-s3 |
| UUIDv7 / 拼音 | google/uuid / go-pinyin | uuid6（3.14 起用标准库 `uuid.uuid7`）/ pypinyin | uuid 11 / pinyin-pro |
| 测试 | testing + testify + rapid | pytest + pytest-asyncio + hypothesis | vitest + **fast-check** |
| 包管理 | Go modules | pyproject，精确版本 | npm + package-lock（与今天一致） |

**TS 为什么这样选**（对照市场方案，都是"每门语言内部只有一种写法"）：

- **Node 24**：bff-mobile 已经跑在 `node:24-slim` 上（graphql@17 需要它）；这是 Active LTS，维护到 2028-04。
- **Fastify 5，而不是 Hono、Express 5 或 NestJS**：
  - 生命周期钩子（onRequest、preHandler、onSend、onError、onTimeout）正好放得下 SDK 的中间件链：request-id、trace 提取、截止时间、鉴权、错误映射、RED 指标、访问日志。
  - 每个成员一个独立的 Fastify 实例，天然隔离。
  - 内置 pino 和 JSON Schema 校验，路由的 schema 可以从 OpenAPI 生成。
  - Hono 面向 Web 标准的 Request，在 Node 上要做适配，连接级超时、请求体上限这些服务端控制较弱。
  - Express 5 没有钩子模型，类型也弱。
  - NestJS 自带一整套依赖注入，等于多一种写法，和"一个入口"冲突。
  - BFF 的 Yoga 挂到 Fastify 上，全项目 TS 只剩一个 HTTP 栈。0103 里写的"Apollo"是文档漂移，顺手改掉。
- **node-postgres，而不是 porsager/postgres、Kysely、Drizzle 或 Prisma**：
  - 需要在每个事务里 `SET LOCAL ROLE` / `search_path` / 超时。porsager 默认隐式缓存预编译语句，和"同一条连接上切换 search_path"有交互风险（foundations-data-platform DB-6 正在验证的问题），只能靠关缓存规避。
  - Kysely 和 Drizzle 是查询构造器或 ORM，Prisma 是 ORM 且带独立引擎，都和 0103 的"手写 SQL、不用 ORM"冲突。Prisma 还做不到每个事务 `SET LOCAL ROLE`。
  - node-postgres 的池参数（`max`、`connectionTimeoutMillis`、`idleTimeoutMillis`）、LISTEN/NOTIFY（pgqueue 的 Notify 要用）、COPY 流，都现成。
- **node-pg-migrate**：支持纯 SQL 文件，状态表可以放进本组件的 schema（`--migrations-schema`），拿锁也是独占连接。Graphile Migrate 绑定了自己的开发流程；dbmate 是一个 Go 二进制，塞进 Node 镜像很别扭。
- **grpc-js，而不是 connect-node**：connect-node 不支持服务配置里的重试和重试预算，服务端也没有 `MaxConnectionAge`，协议 P7.5 / P7.8 做不到。grpc-js 是唯一一个维护中的纯 JS gRPC 实现。ts-proto 能生成 grpc-js 的服务定义，以及 `google.rpc.*` 错误详情的类型。
- **要先做最小复现再铺开**（照记忆里的教训）：
  - grpc-js 的 service config 里，`retryPolicy` 和 `retryThrottling` 是否真的生效；
  - node-pg-migrate 在指定 schema、不建 schema、不写 OWNER 时的行为；
  - 每个成员一个 `BasicTracerProvider`、共用一个导出器，在 Node 上是否可行；
  - pg 池在 `SET LOCAL` 之后归还连接时是否干净。

  这几条列为 §7.7 的任务 R1。

### 5.4 仓库与包结构

| 仓库 | 结构要点 |
|---|---|
| be-sdk-go | 根包 `besdk`：运行时、配置、HTTP、gRPC、鉴权、Access、Store、事件、幂等、Jobs、快照、缓存、错误。子包：`money`、`lifecycle`、`search`、`besdktest`、`shell`。内部包：`internal/pgdialect`、`internal/bus/{jetstream,pgqueue}`、`internal/cold/{none,s3parquet}`、`internal/telemetry`。`examples/widget`、`examples/widget-broken` |
| be-sdk-python | 包 `besdk`，子模块与 Go 一一对应（`besdk.money`、`besdk.lifecycle`、`besdk.testing`、`besdk.shell`、`besdk._internal.*`）；可选安装 `besdk[cold]`（pyarrow）；`examples/widget` |
| be-sdk-ts | 包 `@brickkit/be-sdk-ts`，组件里仍以 `besdk` 别名引用。子路径导出 `/money`、`/lifecycle`、`/testing`、`/shell`；`examples/widget` |

三个仓库都有 `make vectors`，从 be-protocol 的 tag 同步向量并跑一遍，以及 `make conformance`，构建 widget 镜像后调 be-acceptance 的 compconf。

### 5.5 外壳启动器

| 语言 | 启动器 | 外壳仓库 |
|---|---|---|
| Go | `shell.Main(shell.Members{customer.Spec, product.Spec, …})`；成员版本从 `debug.ReadBuildInfo()` 读，与 JSON 里的 `version` 核对 | `be/go-core`、`be/go-infra`、`be/go-backoffice`（T21–T23） |
| Python | `besdk.shell.main([print_spec, …])`；版本从 `importlib.metadata` 读 | `be/py-render`（T24） |
| TS | `runShell([specA, …])`；版本从成员包的 `package.json` 读 | **暂不建外壳仓库**：今天只有 BFF 一个 TS 组件，而 BFF 永远不进外壳（0108）。启动器随 SDK 发布，并对两个 widget 实例跑 compconf 的 `shell` profile，证明它可用 |

三个启动器共用一份语义：P19，外加 apis 文件 §5 的伪代码。

### 5.6 第四门语言

1. **准入**：
   - 作者自己选栈，写进组件 `AGENTS.md` 的 "Stack" 一节；
   - `assembly.yaml` 写上 `protocol: "1.0"` 和 `language: <名字>`；
   - 按 be-protocol 实现协议，建议跑 `vectors`；
   - compconf 里适用的 profile 全部通过，组件就能进 `brickkit.yaml`，**单独运行**。
2. **门禁**：扫源码的门禁（`bare-route-scan`、`identity-literal-scan`、`import-scan` 等）只认官方语言，对第四门语言不适用。替代它们的是 compconf，加上评审时按 apis 文件 §7 的 INTERNAL 清单逐条核对。`compconf-record-scan` 照常适用。
3. **不能进外壳**，直到这门语言有了官方 SDK 和启动器。
4. **第二个组件之前锁栈**：同一门语言要出现第二个组件，先给 0103 加一行（§9 Q2），同时决定要不要做官方 SDK。官方 SDK 的门槛是：
   - 全部向量通过；
   - widget 通过 compconf、busconf、lifecycleconf；
   - 启动器通过 `shell` profile；
   - 有测试包；
   - `02-backend.md` 里有它的一节。
5. **运行成本写明**：JVM / CLR 每个进程常驻 256–512 MiB，冷启动以秒计。对应调大 `healthCheck.startPeriodSeconds` 和 `requests.memory`，并写进 BRICKKIT 的 "Before you deploy"（0105 重写后的 caveat）。
6. **brickKit 的配合**：`mode: local` 可以用 `local.runCommand` 启动任何语言（`brickkit docs 03-component-guide/02-component-yaml-reference`）。镜像、迁移容器、健康检查本来就和语言无关。

---

## 6. 现状盘点：保留、改、删，以及每个 bug 由哪处改动修掉

### 6.1 三门 SDK 的现状（v0.5.0）与去向

| 方面 | 今天 | 去向 |
|---|---|---|
| 模块契约 | Go `Module{HTTPHandler, RegisterGRPC, Start, Stop}`（`module.go:15-20`），构造函数 `func(ctx, *Runtime)`；Python `Module(asgi_app, register_grpc, migrations_dir, start, stop)`（`module.py:13-19`）；TS `Module{httpHandler: Yoga, start, stop}`（`module.ts:14-20`） | **改**：`Spec` + 声明式 `Module`（§5.2）。`HTTPHandler` 变成 `HTTP func(r *Router)`，由 SDK 持有引擎；Python 的 `migrations_dir` 从 Module 挪到 Spec |
| 入口 | Go `RunStandalone`（`standalone.go:50`）、迁移另有 `migrate.Main` 二进制；Python `run_standalone`，迁移各组件自写（print 的 `migrate.py`）；TS `runStandalone` | **改**：`Main(spec)` 一个二进制带 `migrate` 子命令。Python 和 TS 的迁移入口收进 SDK |
| Runtime | 只有导出字段（Go `runtime.go:99-111`：DB、NATS、Logger、Tracer、Meter、Registry…） | **改**：字段不导出，只留方法；`DB` 和 `NATS` 不再对模块开放 |
| Config | 字符串取值，`IntOr` 解析失败时静默回退（`runtime.go:56-75`），`MustString` 会 panic（`:48`）；装着整个进程环境（三门都是） | **改**：严格类型；限定在 `configSchema` 声明过的键上（P2.2、P2.3）；错误一次汇总报出，退出码 78 |
| `Endpoint` | 去掉 scheme（Go `endpoint.go:33`，Python `runtime.py:40-51`） | **保留**语义，挪到 `rt.Conn` / `rt.UserHTTP` 内部 |
| `PGDSN` / `WithTx` | `WithTx(ctx, db, role, schema, fn)`，`search_path` 里带 `_archive`（`tx.go:20-50`）；Python 同构（`tx.py:16-61`） | **删**；换成 `Store` / `Tx`（P10） |
| 池 | Go `sql.Open` 不设上限（`standalone.go:79`、`shell/run.go:113`）；Python 固定 10、等连接没有超时（`standalone.py:103`、`tx.py:56`） | **改**：P10.5 |
| `ListWindow` / `Query` | 默认 90 天窗口（`query.go:25`），Python 是桩代码 | **删**；默认窗口由 `lifecycle.yaml` 的 `tiers.hot` 决定（主数据是 `none`，D3），分页按 P3.8 |
| `BatchGetRouted` | 先查热表，再查 `_archive`，`SELECT *`（`archive.go:21-93`），Python 是桩代码 | **删**（D2）；换成 `BatchGetAll` 分片和服务端上限（P7.10） |
| HTTP 中间件 | Go：request-id、span（不提取上游）、RED、访问日志、错误映射（`gin.go:57-63`）；Python 没有错误映射，路由标签用的是原始路径（`fastapi_app.py:67-80`）；TS 只有 Yoga | **改**：一条完整的链（P3、P18），三门相同；新增截止时间、请求体上限、服务端超时 |
| 错误体 | `{"error": msg}`，非 status 的错误原文直出（`gin.go:134-137`）；Python 是 FastAPI 默认的 `{"detail"}` | **改**：P4 |
| 判定链与路由包装 | `GET/POST…(r, path, perm, h)` + `RequirePermission`（`authz.go:37-194`），三门同构 | **保留**写法，**改**内容：守卫可以是 `PermKey` 或 authzgen 生成的 `Guard`；判定链按 P6.2 |
| bundle 轮询 | v1 格式，15 s，ETag，fail-static；Go 用没有超时的 `http.DefaultClient`（`bundle.go:107`）；Python 遇到异常会悄悄退出循环（`bundle.py:89-91,121`） | **改**：v2，加 poke 和 3 s 超时，受监督（P6.1）；状态从包级全局变量挪进进程级的 `platform` 对象 |
| JWT | 只认 RS256，只要求 sub 和 iat（`jwt.go:52-67`、`jwt_verify.py:49-62`、`jwtVerify.ts`） | **改**：P5 |
| ScopeFilter / ScopeOf | `ScopeFilter{All, HasDept, Prefix, Exact, Owner, In}`，哨兵 `!no-dept`（`scope.go:22-96`）；在 gRPC 上调会 panic | **删**；换成 `AccessFrom` + 规范谓词的数组参数（P6.5）。R60 的语义由"数组为空"天然承载 |
| gRPC 客户端 | `UserClient` / `SystemClient` 每次调用现拨（`client.go:34,49`）；`UserClient` 在 REST 路径上什么都没转发（`:29-33`） | **删**；换成 `rt.Conn` 和 `rt.UserHTTP`（P7、P8） |
| gRPC 服务端 | 只有一元 recovery（`standalone.go:215`）；Python 什么拦截器都没有 | **改**：P7.4、P7.5 |
| 事件 | Go 用核心 NATS 订阅、无重投（`events.go:55-156`），inbox 用 `max(version)` 判重；Python 的 `consume` 是桩代码（`events.py:49`）；TS 没有 | **删**旧 API；换成 `Events` 声明 + JetStream + `besdk_event_cursor`（P12） |
| outbox | Go 用 SKIP LOCKED 认领，但核心发布没有确认（`outbox.go:109-182`）；Python 用裸 `SELECT`，会重复发布（`outbox.py:95-134`）；`PublishOutbox(tx, schema, ev)` 拿不到 ctx | **改**：`tx.Publish(ctx, ev)` + 拿到 PubAck 才算发布的泵（P12.1） |
| 日志 | JSON 带 `component_id`；Go 的 PII 脱敏要手工调（`logging.go:66`）；Python 和 TS 是自动的，并截断到 2 KiB | **改**：P18.2，三门统一自动脱敏和截断 |
| 指标 | 只有 HTTP 两个指标，`status` 用的是文本（`gin.go:28-36`）；TS 根本没有 `/metrics` | **改**：P18.3 |
| OTel | 只有 TracerProvider，没有传播器（`otel.go:21`）；Meter 在三门里都是 no-op；Python 把基础 URL 原样当 traces 端点用（`otel.py:18-45`） | **改**：P18.1；Meter 接上真的 MeterProvider，通过 Prometheus exporter 写进同一个 registry |
| 外壳 | Go `shell.Main(name, Registry)`（`shell/run.go:43-197`）；Python `shell_runner.main`（`shell_runner.py:112-339`）；成员共用外壳的池和连接，忽略成员自己的 `PG_*` | **改**：P19；成员版本核对；成员级预算 |
| 测试辅助 | 没有对外的测试包：Go 只有 `ContextWithClaims`；Python 的假 JWKS 和假 bundle 只在仓库内部的 `tests/helpers.py`；TS 是 `test/helpers.ts` | **新增**：`besdktest`、`besdk.testing`、`/testing`，内容同形（apis 文件 §2.12） |
| DataLoader | TS 的 `createBatchGetLoader` | **保留**，加上 `maxBatchSize` = 下游的上限（D8） |
| `docs/authz-protocol.md` | 三个仓库各一份 | **删**；内容并入 be-protocol 的 P5 / P6，三个 SDK 的 README 链过去 |

### 6.2 已核实的问题 → 协议条款 → SDK 改动

| # | 问题 | 证据 | 协议 | SDK 改动 |
|---|---|---|---|---|
| 1 | HTTP 服务端零超时 | `be-sdk-go/standalone.go:187` | P3.5 | 统一的 serve 函数设四个超时 |
| 2 | 入站请求没有截止时间 | 三门的中间件都没有 | P3.4、P9 | 路由级截止时间写进 ctx / contextvar / ALS |
| 3 | 出站没有截止时间 | `client.go:34,49`、`client.py:56-70`、BFF `restForward.ts:68`、iam `service.go:226-233` | P7.7、P8.2 | `Conn` 和 `UserHTTP` 的拦截器按预算设超时 |
| 4 | 数据库没有任何超时 | `tx.go:32`、`tx.py`；be-ops 只建角色 | P10.3 | `Store.Tx` 每个事务 `SET LOCAL` 三个超时 |
| 5 | bundle 和 JWKS 的拉取没有超时 | `bundle.go:107`（DefaultClient）、TS 的 `fetch` | P5.4、P6.1 | 3 s 超时 |
| 6 | 池没有上限，外壳成员共用 | `standalone.go:79`、`shell/run.go:113,132,274` | P10.5 | `PG_POOL_MAX` + 每个成员一个信号量 |
| 7 | Python 池固定 10，等连接没有上限 | `standalone.py:103`、`shell_runner.py:126`、`tx.py:56` | P10.5 | `max_size` 取同一个键，加取连接超时 |
| 8 | gRPC 每次调用现拨连接 | `client.go:34,49,54-56`、BFF `customer.ts:87-100` | P7.6 | `rt.Conn` 按（成员，依赖，端口）缓存 |
| 9 | 没有 keepalive，没有 `MaxConnectionAge`，没有显式的消息上限 | `standalone.go:215` | P7.5、P7.6 | 服务端和客户端的参数 |
| 10 | 没有重试，也没有重试预算 | 全仓 | P7.8 | 从 `idempotency_level` 生成服务配置，加 retryThrottling |
| 11 | NATS 断线约 2 分钟后永久失联 | `standalone.go:89`、`shell/run.go:123`、`standalone.py:110`、`shell_runner.py:127` | P1.2、P12 | `MaxReconnects(-1)`、`RetryOnFailedConnect`、断线和错误回调；JetStream |
| 12 | 核心发布在没有订阅者时也"成功"，事件就此丢失 | `outbox.go:167` | P12.1 | 拿到 PubAck 才标成 PUBLISHED |
| 13 | outbox 行无限反弹，没有退避也没有告警 | `outbox.go:171-176` | P12.1 | `next_attempt_at` 退避，加 `be_outbox_oldest_age_seconds` |
| 14 | Python 的 outbox 用裸 `SELECT` 认领（多副本重复发布） | `outbox.py:95-134` | P10.9、P12.1 | 与 Go 共用同一段认领 SQL（参考 DDL） |
| 15 | Python 的消费是桩代码 | `events.py:49` | P12 | 实现 `Events` 和 JetStream |
| 16 | 事件 handler 出错后不重投 | `events.go:67-71` | P12.7 | Nak + 退避 + DLQ |
| 17 | 没有 queue group：两个副本各处理一遍 | `events.go:65`、`events.py:41-46` | P12.5 | pull durable，副本之间竞争 |
| 18 | inbox 在分区表上去重失效 | `events.go:136-150`；组件的唯一键是 `(idempotency_key, created_at)`，如 inventory `002:42-64` | P12.6 | 不分区的 `besdk_event_cursor`，用原子 upsert 判重 |
| 19 | 游标按 subject 建键，跨 subject 乱序时记错账 | `events.go:124-126` | P12.6 | 主键 `(consumer, aggregate_type, aggregate_id)` |
| 20 | `hop_count` 和 `causation_id` 从没人填，防环是死代码 | `outbox.go:23-27`、`events.go:82-156`、`events.py:22-23` | P12.8 | `tx.Publish` 从 ctx 里"正在处理的事件"派生 |
| 21 | trace 每一跳都断 | `otel.go`（没有传播器）、`gin.go:99`、`standalone.go:215`、`fastapi_app.py:66-75`、TS | P18.1 | 传播器、otelgrpc、信封里的 traceparent 和 span link |
| 22 | 外壳里所有成员共用一个 `service.name` | `shell/run.go:101` | P19.4 | 每个成员一个 TracerProvider |
| 23 | 访问日志没有 `trace_id`；SDK 内部用 `slog.Default()` | `gin.go:193-199`、`events.go:69,171` | P18.2 | 带 ctx 记日志；SDK 内部一律用成员的 logger |
| 24 | 没有 40001 / 40P01 重试 | `tx.go:20-50`、`tx.py:56-61` | P10.4 | `Store.Tx` 重试 |
| 25 | 没有隔离级别可选，也没有只读快照 | 同上 | P10.4 | `TxOptions`、`ReadSnapshot` |
| 26 | 外壳里成员的后台循环失败后永久停止 | `shell/run.go:164-183`、`shell_runner.py:177-183` | P1.7、P14 | 统一的 Jobs 监督器 |
| 27 | 单跑时 `Start` 出错，进程以 0 退出 | `standalone.go:145-163` | P1.8 | 致命错误一律非 0；循环交给监督器 |
| 28 | 组件的 `Start` 在第一个循环退出时就返回，其余循环成了孤儿 | finance `module.go:54-66` | P14.1 | `Start` 不许起循环；门禁 `module-ticker-scan` |
| 29 | outbox 泵遇到 DeadlineExceeded 静默退出 | `outbox.go:77-79` | P1.7 | 受监督的 `Every` 任务 |
| 30 | 刷新令牌能当访问令牌用 | `jwt.go:52-67`、`jwt_verify.py:49-62`、`jwtVerify.ts` | P5.3 | 校验 `typ`、`iss`、`aud`，`exp` 必填 |
| 31 | Python 拒收所有带 `aud` 的 token（PyJWT 不传 audience 时的行为） | `jwt_verify.py:55-60` | P5.3 | 传入 `audience=TENANT_ID` |
| 32 | 没有 iss 和 aud，一个 IdP 给多套部署签发时 token 会串用 | 同上 | P5.3 | 同上 |
| 33 | gRPC 服务端没有身份；调 `ScopeOf` 就 panic，变成 Internal | `standalone.go:215`、`scope.go:74` | P7.3 | 身份拦截器；`AccessFrom` 答 Unauthenticated |
| 34 | `UserClient` 在 REST 路径上什么都没转发 | `client.go:29-33` | P8.1 | 删掉；换成 `UserHTTP` |
| 35 | 幂等重放没有和 caller、命令、目标绑定（SDK 里没有，组件各写各的，七个变体） | events-consistency §5.1 | P13 | `besdk_idempotency` + `Idempotent` |
| 36 | 分区写死日期（最晚到 2026-10-05），12 份 `partition` 包 | data-layer §4.1 | P11.3、P16.6 | 平台迁移建窗口 + 生命周期引擎的 Singleton 任务 |
| 37 | 外壳静默忽略成员的 `PG_HOST` / `PG_DATABASE` | `shell/run.go:107-113`、`shell.go:42-56` | P19.3 | 不一致就拒绝启动 |
| 38 | 外壳登录角色必须 INHERIT（泵不切角色） | `outbox.go:58,109-122` | P10.2、P19.5 | 所有路径都 `SET LOCAL ROLE` |
| 39 | 错误体泄露内部细节（SQL、token 解析失败的原文） | `gin.go:137`、`authz.go:161`、`authz.py:136-138`；组件的 `status.go` | P4.3 | 映射层强制使用通用文案 |
| 40 | Python 的路由标签用原始路径，指标基数爆炸 | `fastapi_app.py:67-68,79-80` | P18.3 | 在 `call_next` 之后再取路由模板 |
| 41 | TS 没有 `/metrics`，但 component.yaml 声明了它 | bff `component.yaml` | P3.12 | SDK 负责挂出 |
| 42 | Python 外壳把 `"null"` 解析成 TypeError | `shell_runner.py:61-79` | P19.1 | 统一的解析和错误提示 |
| 43 | 外壳钉的 SDK 版本落后（go-core v0.3.0；py-render v0.4.2，而 print 是 v0.4.4） | `shell/be/*/go.mod`、`pyproject.toml:5` | P19.1 | `dependency-version-scan` 扩展到 SDK 版本，外壳和成员必须完全一致 |
| 44 | BatchGet 没有上限；sales 是 N+1 | data-layer §5.1 | P7.10 | `max_items` 拦截器 + `BatchGetAll` |
| 45 | 业务日期取 `time.Now().UTC()`，SQL 里用 `CURRENT_DATE`（组件 bug，SDK 没有入口） | finance `autoentry.go:54`、sales `pricing.go:48-49` | P11.7 | `rt.Calendar()` + 门禁 `business-date-scan` |

---

## 7. 迁移路径

### 7.1 版本

| 对象 | 现在 | 目标 | 说明 |
|---|---|---|---|
| be-protocol | — | `v1.0.0-rc.N` → **v1.0.0**（pilot 结束时） | 冻结之后的修正：措辞走 patch，增补走 minor |
| be-sdk-go / python / ts | v0.5.0 | `v0.6.0-rc.N` → **v0.6.0**（pilot 结束、API 冻结）→ **v1.0.0**（T25 之后，代码不变，只打 tag） | 不用 1.0 起步：pilot 必须有机会改 API，而 Go 一旦到 1.x，改 API 就得换 `/v2` 路径。v1.0.0 只是在 T25 证明之后的一次重新命名；组件在下一次自然发版时换上它，不需要为此单独扫一轮 |
| mdm/org、mdm/currency（新建） | — | **3.0.0** | 本轮新建（用户答复 P2），首版直接用 3.0.0 基线，和其余组件同一个主版本；Go 模块路径 `/v3` |
| 12 个有库的组件 + bff | 2.x | **3.0.0** | Go 模块路径 `/v2` → `/v3`，双 tag 是 `3.0.0` + `v3.0.0`。生成的契约包 `gen/<domain>/<name>` 自己独立版本化：契约只增，所以多数只是 minor |
| 外壳 4 个 | 1.0.0（`members: []`，钉着旧 SDK） | **1.1.0**（第一次带上成员） | 外壳仍在 1.x |
| contract-infra-authz / -iam | — | v2.0.0 / v1.0.0 | F6b 已经同意新建这两个仓库 |
| be-acceptance / be-ops | v0.4.8 / v0.2.0 | 0.5.0 / 0.3.0 | compconf、新门禁；authzgen、资源目录 |
| 前端 | 1.x | 06c 再定 | 依赖错误模型、`/api/me/access` v2、discovery 登录 |

### 7.2 五个阶段

```
A 规范与契约 ─┬─ B 实现（并行 lane） ── C pilot（冻结点） ── D 组件扫一遍（按依赖分批） ── E 外壳 T21–T24 → T25 → v1.0.0
              └─ 决策和约定的草稿（与 A、B 并行）
```

- **A，规范与契约**：
  - be-protocol rc.1：P1–P20 中英两份、schemas、参考 DDL、第一批向量、widget 契约；
  - contract-infra-authz v2.0（authz-architecture 的 P0 形状）；
  - contract-infra-iam v1.0（foundations-data-platform §11.3）。
- **B，实现**：三门 SDK 三条 lane，加 be-acceptance 和 be-ops 两条 lane，五条并行。每条 lane 先做本 lane 的最小复现（§7.9），再写前文列出的红测试，最后实现。
- **C，pilot**：先让三个 widget 都过 compconf；再拿 4 个真实组件，对照它们在 compconf 上的结果修 SDK 和规范：
  - infra/authz 3.0.0：v2 的 provider，有了它，后面才能做真实的端到端；
  - infra/iam-casdoor 3.0.0：claims v2、平台 `sub`；
  - mdm/customer 3.0.0：最简单的 Go 组件；
  - infra/print 3.0.0：Python。

  同一阶段新建 **mdm/org**（法人：时区、会计年度起始月、本位币）和 **mdm/currency**（币种、汇率类型、每日汇率），任务 M1、M2（用户答复 P2）。这样其余组件升 3.0.0 时直接引用真实的法人、币种和汇率，不需要 `LEGAL_ENTITIES` 过渡变量，汇率也不限定为 1。mdm/org 与 IAM 目录（部门）怎么分工，在 mdm/org 自己的设计里定。

  **出口条件**：4 个 pilot 组件、2 个新建的 mdm 组件加 3 个 widget 全绿；SDK API 冻结（v0.6.0）；be-protocol 打 v1.0.0。
- **D，扫一遍**：按依赖分批，批内每个组件一条 lane（§7.7）。
- **E，外壳**：门禁切成报错 → T21–T24 组装 → T25 真机验证 → 三门 SDK 打 v1.0.0。

### 7.3 be-acceptance 门禁的落地顺序

| 顺序 | 门禁 | 内容 | 先警告到哪一步 |
|---|---|---|---|
| 1 | `protocol-config-scan` | configSchema 里有用到的 profile 需要的键，类型和密钥标记都对；不再出现 `AUTHZ_BUNDLE_URL` | B 结束 |
| 2 | `migration-identity-scan`、`identity-literal-scan` | data-layer §2.6；外加禁止 `BIGSERIAL` 主键、禁止 `NUMERIC(18,2)` 金额列（`id-type-scan`、`money-precision-scan` 并入这里） | C 开始（新基线一律报错） |
| 3 | `platform-table-scan` | 组件的 SQL 不碰 `besdk_*`；不手写 inbox、幂等、游标的 SQL（取代 events-consistency §6 第 6 条） | C 开始 |
| 4 | `lifecycle-scan` | data-lifecycle-v2 §5.3 | C 开始 |
| 5 | `business-date-scan` | SQL 里出现 `CURRENT_DATE` / `now()::date` / `date_trunc(…, now())` 就报错 | C 开始 |
| 6 | `batch-cap-scan`、`idempotency-level-scan` | data-layer D8；foundations-communication §5.7 | C 开始 |
| 7 | `error-catalog-scan` | `contracts/errors.yaml` 存在且格式正确；官方语言的代码里用到的 reason 都登记过 | D 开始 |
| 8 | `authzgen-fresh`、`authz-capability-scan`、`perm-key-usage-scan` | authz-architecture §5.4、identity §3.3g | D 开始 |
| 9 | `module-ticker-scan`、`module-global-cache-scan`、`besdktest-import-scan` | 模块里不许自己写循环、包级缓存；生产代码不许 import 测试包 | D 开始 |
| 10 | `sdk-version-scan` | 扩展 `dependency-version-scan`：同一门语言的组件和外壳钉同一个 SDK 版本；外壳等于它成员的版本 | E 开始 |
| 11 | `compconf-record-scan` | §4.6 | 对 3.0.0 及以上的组件一律报错 |
| 12 | `connection-budget-scan` | 所有进程的 `PG_POOL_MAX` 之和，加上迁移和 Casdoor 的预留，小于 `max_connections` 减去保留 | E 开始 |
| 后来 | `contract-migration-scan`、Squawk | foundations-data-platform §6.4 | 06c 之后 |

**改**：

- `bare-route-scan` 认新的路由写法：Go 的 `besdk.GET`、Python 的 `@r.get`、TS 的 Fastify `r.get`；
- `data-scope-test-scan` 认 404；
- `dependency-version-scan` 支持 `/v3`。

**退役**：`system-client-scan`（identity §5.3：它的前提不成立）。

**versionbump 工具**：要支持主版本跳到 `/v3`（改模块路径、改全部 import、改外壳的 `go.mod`），这是任务 A9。

### 7.4 每个组件 3.0.0 的统一清单

1. **依赖**：SDK v0.6.0。Go 的模块路径改成 `/v3`。
2. **重建迁移基线**：删掉旧迁移，写一份新的 `0001_init`：
   - 主键用 `uuid`（UUIDv7）；
   - 金额、单价、数量按 P11.6 的精度，金额与币种成对；
   - 交易单据带 `legal_entity_id`；
   - 业务日期是 `DATE` 列；
   - 不出现 `OWNER TO`、日期分区、`_rw`；
   - 平台表**不写**进组件的迁移，由 SDK 的平台迁移负责。

   这一条需要决策 0305 明文破例（§7.6）。
3. **`lifecycle.yaml` v1**，初稿见 data-lifecycle-v2 §6.1。
4. **模块改写**：
   - `Spec` / `Module`；
   - `Store`；
   - 声明 `Events`；
   - `Jobs`（删掉 `partition/` 包和所有 ticker）；
   - `Reconcilers`、`Snapshots`；
   - `AccessFrom` + 规范谓词（P0 就带上 acl 分支，投影先为空）；
   - `Idempotent`；
   - `Errorf` + `contracts/errors.yaml`；
   - 业务日期走 `rt.Calendar()`，单据号走 `NextNumber`。
5. **契约，只增**：
   - 新字段：`legal_entity_id`、`currency`、业务日期；
   - 事件契约加 `x-aggregate-type` 和 `x-consumption`；
   - proto 加 `max_items` 和 `idempotency_level`；
   - `errors.yaml`；
   - be-ops 把资源契约片段并进组件的 openapi。
6. **`assembly.yaml`**：`protocol: "1.0"`、`resources`、`requires_capabilities`、`type: field` 的键、`conformance.fixtures`。`.admin` 键在 `permissions.tsv` 里标 deprecated（只增不删）。
7. **配置**：
   - configSchema 按 `config-keys.yaml` 写；
   - 新增 `AUTHZ_URL`、`IAM_ISSUER`、`TENANT_ID`、`EVENT_BUS_URL`、`DATA_LIFECYCLE`、池的几个键（法人日历来自 mdm/org，不是配置键）；
   - 删掉 `AUTHZ_BUNDLE_URL`；
   - `config/vars.yaml` 在同一批里一起改，并核对 `service-hostname-scan`（记忆里的 C18）。
8. **测试**：
   - 改用 `besdktest`，每个连库测试都在随机身份下跑；
   - 每个消费者一条"乱序加重复的终态等于按序"的属性测试；
   - 前文列出的本组件红测试先提交、先跑红。
9. **文档**：BRICKKIT（"Before you deploy"写通用表述，加一节"数据与保留"）、AGENTS、design.md，中英两份。
10. **种子数据**：
    - id 全换成 UUIDv7；
    - 加第二个法人「本地测试」华南子公司；
    - 首个管理员改用 `BOOTSTRAP_ADMIN_SUB`（I4）；
    - `db-reset` 之后重新播种。
11. **验收**：compconf 报告 → `brickkit upgrade` → `make verify` → `brickkit down`（记忆：验证完一定要关）。

### 7.5 各组件特有的改动（汇总前文，版本统一是 3.0.0）

| 组件 | 特有改动 |
|---|---|
| infra/authz | v2 provider 的 P0 部分：档位（含 `dept`）、维度取值、字段键、能力、revision。ResolveClaims v2 带 `tenant_id`。审计事件走 outbox，带 actor。改部门写 stale。superuser 自动补齐键；系统角色和最后一个管理员受保护。`/api/me/access` v2。元组表和 changes 端点的形状一次建齐，`sharing` 能力随 P1 打开。`provides_capabilities`、`RESOURCE_CATALOG`、`DATA_SCOPE_CATALOG` |
| infra/iam-casdoor | 删掉对 authz 的依赖边，改读 `AUTHZ_URL`。签 `typ`、`iss`、`aud`、`jti`、`tenant_id`、`locale`。平台 `sub` + `identity_links`。`/api/iam/login-config`。按 RFC 8693 的形状换 token（`casdoor_id_token` 留作别名，直到 06c 的前端改掉）。`User` 加 `version` 和 `disabled`；新增 `deleted` 事件。webhook 投递改成 `Queue` / `Reconciler`。登录调 authz 带上截止时间 |
| mdm/customer | 主数据去掉默认窗口（D3）。`credit_limit (19,4)` + 币种；字段键 `mdm.customer.credit`。gRPC 写接口答 Unauthenticated（I5）。幂等的先查后插 → SDK 认领 |
| mdm/org（新建） | 法人主数据：时区、会计年度起始月、本位币；发布法人变更事件，SDK 的快照帮手据此维护法人日历（P11.9）；与 IAM 目录（部门）的分工在它的 design.md 里定 |
| mdm/currency（新建） | 币种（ISO 4217 小数位）、汇率类型、每日汇率；和其他 mdm 枢纽一样，谁都读它，它不调用任何人；汇率的来源（集成组件或手工录入）换了，消费方不受影响 |
| mdm/product | `standard_cost (19,6)`、字段键 `mdm.product.cost`、`product_uom_conversions`、I5 |
| erp/inventory | 仓库、流水、预留带 `legal_entity_id`。删 `warehouse_access` 和三个端点（I7）。多品预留按 `(warehouse_id, product_id)` 排序加锁。预留 TTL + `HoldReservation` + 清扫（`Every`）。批次和序列号校验：读 product 快照，靠回填维护（E6 甲）。幂等放到仓库授权之后 |
| erp/finance | 过账日期取单据的业务日期，按法人日历换算，DATE 与 DATE 比较（修 B-1 到 B-4）。"开会计年度"命令，支持起始月（D7、F5）。凭证号按期连续（F8）。消费 `sales.order.cancelled.v1`。额度快照读穿透，缺失时记 `credit_check_pending`（E7）。信用敞口按法人限定（I9）。删 `legal_entity_access`。原币和本位币双金额。`LockPeriod` 调 `tx.Seal`。ledger 不放 pii |
| erp/sales | `CONFIRMING` 状态 + Reconciler（E8，持有 900 s）。`credit.rejected` 改成 `Enqueue`，不再持锁调网络。赢单的 handler 改成 `Run`。`order_no` 走 `NextNumber`。法人、币种。价格生效日按法人日历（修 `CURRENT_DATE`）。字段键 `erp.sales.pricing.*`。资源可共享，列表加 `view=shared\|visible`。R62 改为 404。`BatchGetOrder` 的 N+1 |
| crm/opportunity | 删掉 `customer_snapshots` 的消费者（E6）。幂等越权的三处修复。法人。资源可共享。预留团队关系 `member: {owned_by: component}` |
| infra/workflow | `.admin` 换成 `all` 档。`CloseTask` / `CancelTask` 的幂等带 `Target`。超期扫描改成 `Every` / Reconciler。操作人取 `ActorSub` |
| infra/notification | `user_contacts` 改用快照帮手，读穿透 iam（需要 iam 3.0.0 的 `User.version`）。`.admin` 换成 `all` 档 |
| integration/im-dingtalk | 派发的 handler 改成 `Run`。`confirmLater` 改成持久的 Reconciler。钉钉 token 跨副本刷新用 `tx.Lock` |
| infra/print（Python） | 迁移入口收进 SDK（`besdk.main` 的 `migrate`）。outbox 的问题随 SDK 一起修掉。actor 取 `system()`。`RenderToObject`（claim-check）放到 P1 |
| infra/bff-mobile（TS） | SDK v0.6 + Fastify。`rt.client` 缓存 gRPC 连接。`userHttp` 带超时和预算。DataLoader 的 `maxBatchSize`。GraphQL 错误的 extensions。只留 `infra.bff-mobile.use` 一个键（I6）。透传 `X-Authz-Revision`。挂出 `/metrics`。仍然不连库 |

### 7.6 要写或改写的决策与约定

> 决策编号由文档 lane 统一分配。下面写的是建议的位置。phase 06 期间写的决策原地改写、编号不变（`docs/en/02-decisions/README.md`）。

**改写**

- **0105**，标题改为 "Any language, one protocol"。草稿：
  - *Decision*：组件可以用任何语言写。语言之间的契约是组件协议（be-protocol）。一个组件，只要它当前版本的 compconf 报告全绿，就可以进项目单独运行。外壳只装同一门语言、同一个 SDK 版本的成员，所以要进外壳，这门语言先得有官方 SDK 和外壳启动器。
  - *Why*：组件可替换、按需求选生态；规则靠黑盒测试保证，不靠语言保证。
  - *Rules out*：
    - 跨语言合进一个进程（sidecar、嵌入式运行时）；
    - 没有 compconf 报告的组件；
    - 为某一个组件在官方 SDK 里加语言特例。
  - *Caveat*：JVM / CLR 每个进程常驻 256–512 MiB、冷启动以秒计，组件 BRICKKIT 的"Before you deploy"必须写明。
  - *Revisit*：协议无法表达某个语言生态的必需能力。
- **0103**，改为 "One locked stack per language that has an official SDK"。
  - 表里加上 TS 一行（§5.3），把 Apollo 改正为 Yoga，并说明 TS 不再只能做 BFF。
  - 新规则：一门语言出现第二个组件之前，先锁定它的栈（加一行）。在那之前，唯一的那个组件自己选栈、写进它的 `AGENTS.md`。
- **0101**：可以跨边界的东西加两类。一是族契约包（只有生成物和契约文件）；二是 be-protocol 的测试数据（向量和 schema，拷贝而来，不是代码）。
- **0108**：外壳 = 一门语言、一个 SDK 版本；每门语言一个启动器；启动时核对成员版本。
- **0106**：总线可以换，方式是 SDK 适配器加 URL scheme，适配器必须过 busconf。这不是一个"开关"。
- **0107**：只剩 `AUTHZ_URL`；新增 `IAM_ISSUER`、`TENANT_ID`。
- **0201**：没有缓存服务器，缓存经 `besdk.Cache`。
- **0202 / 0203 / 0204 / 0205 / 0206**：authz-architecture §6.3。
- **0301**：金额的精度、金额与币种成对。
- **0102**：Revisit 补上"每个成员一个池"（方案 C）和 Citus。

**新增**

| 位置 | 决策 |
|---|---|
| 01-architecture **0109** | 组件协议加黑盒一致性测试；官方 SDK 是参考实现；不允许 SDK 里有规范没写的行为（§3.2） |
| 02-permissions 0207–0211 | authz-architecture §6.3 |
| 03-contracts-and-data 0304 | BatchGet 有上限，上限是契约的一部分（D8） |
| 03-contracts-and-data **0305** | 3.0.0 的一次性破例：已发布的迁移可以整体替换为新基线，前提是**没有生产数据**。写明判据和"仅此一次"；以后同样的情况要重新拍板 |
| 03-contracts-and-data 0306–0308 | 主键用 UUIDv7、单据号由 SDK 分配；业务日期与法人日历；租户 = 部署，法人是维度（F1–F5） |
| 05-runtime 0501–0508 | foundations-communication §11.3：事务里不发网络调用；隔离与重试；截止时间与重试预算；错误模型与 reason 登记表；CloudEvents 信封与聚合流游标；至少一次送达与建流；后台工作只经 Jobs；边缘只路由、鉴权在服务 |

**约定**

| 文件 | 改什么 |
|---|---|
| `02-backend.md` | 整篇重写成"用官方 SDK 写组件"，每节链到对应的 P 章节；新增"用其它语言写组件"一节 |
| `04-configuration.md` | 共享键表（P2）；Database roles 一节按 R63 改写 |
| `06-testing.md` | 测试层次加上"向量"和"compconf"；`besdktest` 的随机身份；每个消费者一条乱序属性测试 |
| `07-registries.md` | 去掉 `_archive`；加 `resource-types.tsv`、`data-subjects.tsv` 和 bucket 列 |
| `01-development-workflow.md` | 发版流程加 compconf 一步；版本规则加上协议版本 |
| `05-data.md` | 两个法人；UUID 种子 |
| 根 `AGENTS.md` 的 Pitfalls | **加**：手写 `besdk_*` 表的 SQL；事务里发网络调用；模块里自己写 ticker；跨请求缓存 `Can`；SQL 里用 `CURRENT_DATE`；主键用 `BIGSERIAL`；金额用 `(18,2)` 或浮点；读没声明的配置键；列表漏了 acl 分支（List/Can 不一致）；按掩码字段排序；把事件 payload 原样展示给人；交易单据缺法人。**改**："`SET ROLE` 漏写 LOCAL"、"`os.Getenv`"、"`gin.New()`"这几行改成"绕过 SDK 的入口"一类说法。**删**：`SystemClient` 那一行（API 已不存在） |

### 7.7 任务清单（带依赖，按 lane 划分）

| ID | 任务 | lane | 依赖 | 产出 |
|---|---|---|---|---|
| R1 | 最小复现（§7.9），每条一个独立目录 | 各 lane 的第一步 | — | `dev/phase-06/to-verify.md` 的结论 |
| S1 | be-protocol rc.1：P1–P20 中英文、schemas、参考 DDL | Spec | 用户已同意新建仓库（答复 P1） | tag `v1.0.0-rc.1` |
| S2 | 第一批向量：authz core、money、幂等指纹、信封派生、日历、编号、错误映射、配置解析 | Spec | S1、K1 | `vectors/` |
| S3 | widget 契约：openapi、proto、events、errors.yaml、lifecycle.yaml、assembly.yaml、fixtures.yaml，以及行为说明 | Spec | S1 | `fixtures/widget/` |
| K1 | contract-infra-authz v2.0 | Authz 契约 | authz-architecture | 契约仓库 |
| K2 | contract-infra-iam v1.0 | IAM 契约 | foundations-data-platform §11.3 | 契约仓库 |
| G1–G11 | be-sdk-go：运行时 / 配置 / HTTP / 错误 / 鉴权 / 可观测（G1）→ Store / pgdialect / 平台迁移（G2）→ 事件（G3）→ 幂等（G4）→ Jobs / Reconciler（G5）→ Access / 投影 / 资源契约（G6）→ 生命周期 P0（G7）→ 日历 / money / ID / 编号 / 搜索 / blob / 缓存 / 快照（G8）→ besdktest（G9）→ 外壳启动器（G10）→ widget 和坏变体（G11） | Go | S1–S3、K1 | `v0.6.0-rc.N` |
| P1–P11 | be-sdk-python，同上 | Python | 同上 | 同上 |
| T1–T11 | be-sdk-ts，同上；数据库、迁移、事件是从零写 | TS | 同上 | 同上 |
| A1–A9 | be-acceptance：compconf 骨架与四个假服务（A1）→ core / obs / err / auth（A2）→ scope / grpc / outbound（A3）→ events / idem / db / jobs / lifecycle / blob（A4）→ shell（A5）→ 套件自检（A6）→ 新门禁先警告（A7，§7.3）→ authzconf core、busconf、lifecycleconf 的向量与黑盒（A8）→ versionbump 支持 `/v3` 和 SDK 版本（A9） | Acceptance | S1–S3；A3 及以后依赖 G11 / P11 / T11 里至少一个 | be-acceptance 0.5.0 |
| O1 | be-ops：authzgen（三门语言）；`resources` / `requires_capabilities` / `field` / `delegable` 的校验；`resource-types.tsv`、`data-subjects.tsv`；不再建 `_archive`；`GRANT … WITH INHERIT FALSE, SET TRUE`；角色级超时；资源契约 openapi 的合并 | Ops | K1 | be-ops 0.3.0 |
| D1–D4 | 决策（D1）、约定（D2）、foundations 的 `02-languages-and-component-protocol.md`（D3）、根 AGENTS（D4），中英两份 | Docs | 和 S1 并行；定稿依赖 C 阶段 | — |
| M1–M2 | 新建 mdm/org（M1）、mdm/currency（M2），两条并行（答复 P2） | 组件 lane ×2 | G、P、A2–A4、O1 | 3.0.0 + compconf 报告 |
| X1–X4 | pilot：authz → iam → customer、print（后两个并行；customer 的额度带币种，依赖 M2） | 组件 lane | G、P、A2–A4、O1；customer 另依赖 M2 | 3.0.0 + compconf 报告 |
| F1 | 冻结：修完 pilot 发现的问题；SDK v0.6.0；be-protocol v1.0.0 | 控制者 | X1–X4、M1–M2 | tag |
| W1 | 第一批：mdm/product、infra/workflow、infra/notification、integration/im-dingtalk | 组件 lane ×4 | F1 | 3.0.0 |
| W2 | 第二批：erp/inventory、erp/finance | ×2 | W1（product、workflow） | 3.0.0 |
| W3 | 第三批：erp/sales、crm/opportunity | ×2 | W2 | 3.0.0 |
| W4 | infra/bff-mobile | TS | W3（它钉的版本） | 3.0.0 |
| E1 | 门禁全部切成报错；`config/vars.yaml` 和 `brickkit.yaml` 的最终一致性 | 控制者 | W1–W4 | — |
| H1–H4 | 外壳 T21–T24：go-core、go-infra、go-backoffice、py-render，1.1.0 | 外壳 lane ×4 | E1 | 1.1.0 + compconf 的 shell 报告 |
| H5 | T25 真机验证：NOINHERIT；四类后台路径；拆回单跑的一致性 | 控制者 | H1–H4 | 测试记录 |
| F2 | 三门 SDK 打 v1.0.0；文档定稿 | 控制者 | H5 | tag |

可以并行的部分：

- A 阶段的 S、K、D 三组；
- B 阶段的 G、P、T、A、O 五条 lane；
- W1 批内四条；W2、W3 批内各两条；
- H1–H4。

按记忆里的规则，**每一批结束都停下来等确认**；tag 和推送由控制者在审查之后统一做。

### 7.8 外壳 T21–T24 之前必须完成的

1. 三门 SDK 是 v0.6.0：外壳的代码和 `go.mod` 就是 SDK 的 `shell` 包，晚做就得再组一次外壳。
2. P19 的全部内容：每个成员一个 provider 和一份预算；成员版本核对；配置不一致就拒绝启动；监督器；汇总的 `/metrics`。
3. 13 个组件加新建的 mdm/org、mdm/currency 全部到 3.0.0，并且 compconf 全绿。成员的 `/v3` 路径决定了外壳 `go.mod` 的内容。
4. be-ops 生成 NOINHERIT 的授权；不再建 `_archive`。
5. `config/vars.yaml` 改用成员自己的服务名：`AUTHZ_URL`、`IAM_JWKS_URL`、`IAM_ISSUER`（0107 / C18）。
6. 门禁 `sdk-version-scan`、`compconf-record-scan`、`dependency-version-scan` 都已经是报错模式。

**不必**在外壳之前做的（P1 及以后）：

- 事件总线的 pgqueue 适配器（F10 要建，但不阻塞外壳）；
- 冷层适配器；
- 共享（`sharing`）、字段掩码在前端的端到端；
- authz-static、authz-openfga；
- iam-keycloak；
- 边缘路由生成器；
- Secret 端口的文件热更新；
- 搜索帮手的 bigm 策略。

这些都在 P0 时把契约形状定好，之后只开能力、只加适配器。

### 7.9 风险与先做的最小复现（R1）

| # | 要验证的假设 | 为什么要先验证 |
|---|---|---|
| 1 | Go：每个成员一个 `TracerProvider` 共用一个 `BatchSpanProcessor` 的导出器；otelgrpc 的 stats handler 用的是成员自己的 provider，不是全局的 | 外壳的核心不变量；otelgrpc 默认读全局 provider |
| 2 | grpc-go：按 proto 方法选项生成的 `WithDefaultServiceConfig`（retryPolicy + retryThrottling）真的生效；`MaxConnectionAge` 触发 GOAWAY 后客户端透明重连 | P7.5、P7.8 |
| 3 | grpc-js：同样的两点 | 选 grpc-js 的前提 |
| 4 | asyncpg 和 pg：`SET LOCAL ROLE` / `search_path` 之后，预编译语句缓存不会跨 schema 串用（DB-6） | P10.2 在外壳里的正确性 |
| 5 | PG16：`GRANT m TO shell WITH INHERIT FALSE, SET TRUE` 之后，`SET LOCAL ROLE m` 可用，而外壳角色对成员的表没有权限 | P19.5 |
| 6 | golang-migrate（iofs）、yoyo、node-pg-migrate 都会忽略 `migrations/lifecycle.yaml`，并且状态表都能放进组件自己的 schema | data-layer §6 第 1 步已经点名的问题 |
| 7 | nats.go、nats-py、nats.js 的 JetStream pull consumer：durable 命名、`DeliverAll`、`BackOff` 与 `MaxDeliver` 的配合、`InProgress` | P12.5–P12.9 |
| 8 | Fastify：同一个进程里起多个实例、各自监听一个端口、各自一套钩子 | TS 外壳启动器 |
| 9 | Casdoor：access token 的 `aud`；discovery 加 PKCE 能不能在浏览器端完成 | iam 3.0.0 和前端 |
| 10 | Python 3.14：asyncpg、grpcio、pyarrow 的 wheel 是否齐全 | 决定 Python 的运行时版本 |

最小复现失败时，在 lane 里改设计，并在报告里写明，不在真实仓库上硬铺开（记忆："没验证过的机制先写最小复现"）。

---

## 8. brickKit 可以支持或推荐的（候选，交给 lane E 处理）

> 按记忆里的规则，下面全部是**候选**："不支持"的判断来自 `brickkit docs`（v1.1.0）和源码仓库 `docs/en/` 的检索，还没有在重建后真机复现。lane E 先把它们放进 `dev/phase-06/to-verify.md`；分成"问题"（必须验证）和"功能请求"（问能不能支持）两类。和前文重复的只列编号，不再展开。

| # | 候选 | 依据 | 对所有用户的好处 |
|---|---|---|---|
| B1 | （→ FR06-014）**configSchema 片段复用**：configSchema 可以引用一个版本化的外部片段，例如 `$ref: be-protocol@1.0#/config/db`，由 `brickkit lint` 展开校验 | 协议级配置键大约 25 个，要在 13 个组件里各抄一遍；docs 里找不到 `$ref` 或片段机制（data-lifecycle-v2 §8 第 3 条也提过） | 任何"一组组件共用同一套运行时约定"的项目，都不用手抄配置 schema |
| B2 | （→ FR06-008）`extraPorts[].protocol` + 可选的 headless 伴生 Service | foundations-communication §12 F1 | — |
| B3 | （→ FR06-006）**readiness 和 liveness 分开配路径**：component.yaml 可选 `readinessCheck.path`。K8s 的 readinessProbe 打它，compose 可以忽略 | 生成器今天让 startup、readiness、liveness 三个探针都打健康检查路径（`06-architecture/04-deploy-file-generation`）；协议的 `/readyz` 没地方接（P1.4） | 滚动更新时不把流量给还没拿到 bundle 的实例，又不违反"健康检查只查自己" |
| B4 | （→ FR06-009）优雅停机时长 `deployment.stopGracePeriodSeconds` | docs 里找不到 stopGrace / terminationGrace；P1.6 需要平台的宽限期大于 `SHUTDOWN_GRACE` | — |
| B5 | （→ FR06-029（新））**组件的语言声明**，例如可选的 `runtime.language`：`brickkit status` / `graph` 里显示；`lint` 检查外壳成员的语言和外壳一致 | 今天只有给 `mode: local` 用的 `local.language`。外壳一个进程只能装一门语言，这条约束 brickKit 看不见 | 多语言项目在组装期就能发现"把 Python 成员塞进 Go 外壳" |
| B6 | （→ brickKit v1.1.0 已支持（OCI label `io.brickkit.shell.members` + `IMAGE_STALE`）；go.mod 那一半仍是本项目的门禁；见 to-verify V-17）**外壳镜像自报成员版本**：`brickkit build` 给外壳镜像打 OCI label `io.brickkit.shell.members`；`up` 时和 `shell.members` 比对 | 根 AGENTS 易错点："go.mod 与 shell.members 不一致 → 镜像跑的是别的代码，没有任何报错" | 把一个静默的坑变成组装期的错误 |
| B7 | （→ FR06-013）迁移容器可以单独覆盖少量环境变量（`PG_MIGRATION_HOST`） | foundations-data-platform §15 第 2 条 | — |
| B8 | （→ FR06-012）密钥以文件挂载的形式交付 | 同上，第 3 条 | — |
| B9 | （→ FR06-002 / FR06-003）**09-patterns 增加一页"多语言组件：协议 + 黑盒一致性套件"**，以及"族契约仓库 + 一致性套件"（同 foundations-communication §12 F8、data-lifecycle-v2 §8 第 6 条） | 本项目是它的实例：规范、向量和夹具放在契约仓库；每门语言一个参考实现；对容器做黑盒测试（本项目里组件协议套件的路径是 `tools/be-acceptance/conformance/component/`，C1） | 给 AI 一个可以照做的"可替换、可换语言"的验收方式 |
| B10 | （→ FR06-001）按槽位声明依赖（`dependencies.slots`） | foundations-data-platform §15 第 1 条 | — |
| B11 | （→ FR06-005）事件的发布和订阅声明，只用于 `graph` / `status` 展示 | foundations-communication §12 F7 | — |
| B12 | （→ FR06-020）把"并存的版本"暴露给迁移进程 | foundations-data-platform §15 第 4 条 | — |
| B13 | （→ 不提：brickKit 有意只校验键名（`11-reference/04-config-schema-spec`））`lint` 和 `up` 按 configSchema 的 `type` 校验字面值 | 同上，第 7 条；协议 P2.3 在运行期做了同样的事 | 错误提前到组装期 |
| B14 | （→ FR06-028（新））**发版前钩子**，例如 `release.checks: [make conformance]`：`brickkit release` 跑完之后才打 tag | 发版流程（§4.6）要求"先有 compconf（`tools/be-acceptance/conformance/component/`）报告，再打 tag"，今天只能靠技能文档约束；先要核实 `brickkit release` 有没有类似的钩子 | 任何项目都能把自己的验收挂到发版上 |

---

## 9. 要用户拍板的点

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| ★Q1 | **新建 GitHub 仓库 `brickKit/be-protocol`**，放规范、schema、向量和夹具契约 | **已答复（P1）：建**，与三个 SDK 平级、单独发版（v1.0.0 起），建仓库那一刻先告诉用户。原推荐理由：规范不属于任何一门语言，而且必须和向量同一个版本号（§3.1） | 先放在 `tools/be-acceptance/protocol/`，目录结构不变，以后再搬出去。代价是规范的版本和套件的版本绑在了一起 |
| ★Q2（已定 P3：同意） | **同一门语言出现第二个组件之前，必须先锁栈**（给 0103 加一行），并决定要不要做官方 SDK | 同意。不锁栈，同一门语言里就会有两套写法，而且永远进不了外壳 | 允许一门语言内多套栈，只能单独运行，靠 compconf 守住 |
| Q3 | **法人和汇率的主数据什么时候建**：`mdm/org`（法人、时区、会计年度起始月）、`mdm/currency`（F4） | **已答复（P2）：这一轮就建**，排在其余组件升 3.0.0 之前（§7.2 阶段 C 的 M1、M2）；不设 `LEGAL_ENTITIES`，汇率不限定为 1。以下是原推荐，已被否决：不放进这一轮。法人先用共享变量 `LEGAL_ENTITIES` 过渡（P11.9）；币种列和汇率列这一轮都建好，但汇率限定为 1（只允许本位币单据），等 `mdm/currency` 建成再放开。两个组件排在外壳之后，作为 P1 的第一批新组件 | 现在就建两个新组件，放进 D 阶段第一批。代价是多两个组件；finance 和 sales 要多等一批 |

---

## 附录 A：平台表参考 DDL（规范性，be-protocol `sql/platform/`）

所有表都在组件自己的 schema 里，由 SDK 的平台迁移以 `PG_USER` 建，所以属主天然就是 `PG_USER`。生命周期的五张表见 data-lifecycle-v2 §4.14，表名照用，不在这里重复。

```sql
CREATE TABLE IF NOT EXISTS besdk_platform_version (component TEXT PRIMARY KEY, version INT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());

-- 事件发件箱：按 created_at 每周一个分区，由生命周期引擎维护（platform 类，全部 PUBLISHED 之后保留 14 天）
CREATE TABLE IF NOT EXISTS besdk_outbox (
  id                 UUID        NOT NULL,             -- UUIDv7 = ce-id = Nats-Msg-Id
  created_at         TIMESTAMPTZ NOT NULL,             -- = IDTime(id)
  subject            TEXT        NOT NULL,
  aggregate_type     TEXT        NOT NULL,
  aggregate_id       TEXT        NOT NULL,
  aggregate_version  BIGINT      NOT NULL,
  occurred_at        TIMESTAMPTZ NOT NULL,
  traceparent        TEXT        NOT NULL DEFAULT '',
  causation_id       TEXT        NOT NULL DEFAULT '',
  hop_count          INT         NOT NULL DEFAULT 0,
  headers            JSONB       NOT NULL DEFAULT '{}', -- 其它 ce-* 扩展属性（如 legalentity）
  payload            JSONB       NOT NULL,
  status             TEXT        NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','SENDING','PUBLISHED')),
  attempts           INT         NOT NULL DEFAULT 0,
  next_attempt_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed_until      TIMESTAMPTZ,
  published_at       TIMESTAMPTZ,
  last_error         TEXT        NOT NULL DEFAULT '',
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE INDEX IF NOT EXISTS besdk_outbox_due ON besdk_outbox (next_attempt_at) WHERE status <> 'PUBLISHED';

-- 认领（每个副本、每一轮）
-- UPDATE besdk_outbox SET status='SENDING', claimed_until=now()+interval '30 seconds'
--  WHERE (id, created_at) IN (SELECT id, created_at FROM besdk_outbox
--          WHERE (status='PENDING' AND next_attempt_at<=now()) OR (status='SENDING' AND claimed_until<now())
--          ORDER BY created_at, id LIMIT 256 FOR UPDATE SKIP LOCKED)
--  RETURNING *;

-- 消费游标：不分区，seen_at 超过 30 天按行清理（E12 的明文例外）
CREATE TABLE IF NOT EXISTS besdk_event_cursor (
  consumer          TEXT        NOT NULL DEFAULT '',   -- 投影名；'' 是组件的默认投影
  aggregate_type    TEXT        NOT NULL,
  aggregate_id      TEXT        NOT NULL,
  version           BIGINT      NOT NULL,
  event_id          TEXT        NOT NULL,
  seen_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (consumer, aggregate_type, aggregate_id)
);
CREATE INDEX IF NOT EXISTS besdk_event_cursor_seen ON besdk_event_cursor (seen_at);
-- 判重即推进；没有返回行 = 重复或旧版本，跳过（和 handler 在同一个事务里）
-- INSERT INTO besdk_event_cursor (consumer, aggregate_type, aggregate_id, version, event_id)
-- VALUES ($1,$2,$3,$4,$5)
-- ON CONFLICT (consumer, aggregate_type, aggregate_id) DO UPDATE
--    SET version=EXCLUDED.version, event_id=EXCLUDED.event_id, seen_at=now()
--  WHERE besdk_event_cursor.version < EXCLUDED.version
-- RETURNING 1;

-- 命令幂等：不分区，按 expires_at 清理（30 天）
CREATE TABLE IF NOT EXISTS besdk_idempotency (
  caller          TEXT        NOT NULL,                -- user:<sub> | svc:<component> | system
  idempotency_key TEXT        NOT NULL,
  command         TEXT        NOT NULL,
  target          TEXT        NOT NULL DEFAULT '',
  request_hash    BYTEA       NOT NULL,                -- sha256(JCS(请求里参与指纹的字段))
  status          TEXT        NOT NULL DEFAULT 'CLAIMED' CHECK (status IN ('CLAIMED','DONE')),
  result          JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (caller, idempotency_key)
);
CREATE INDEX IF NOT EXISTS besdk_idempotency_expires ON besdk_idempotency (expires_at);

-- Jobs
CREATE TABLE IF NOT EXISTS besdk_job_lease (name TEXT PRIMARY KEY, holder TEXT NOT NULL, epoch BIGINT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ NOT NULL);
CREATE TABLE IF NOT EXISTS besdk_job_slot  (name TEXT NOT NULL, slot_at TIMESTAMPTZ NOT NULL, holder TEXT NOT NULL,
                                           started_at TIMESTAMPTZ NOT NULL DEFAULT now(), done_at TIMESTAMPTZ, result TEXT,
                                           PRIMARY KEY (name, slot_at));
CREATE TABLE IF NOT EXISTS besdk_job_queue (
  id UUID PRIMARY KEY, kind TEXT NOT NULL, args JSONB NOT NULL, unique_key TEXT,
  run_at TIMESTAMPTZ NOT NULL DEFAULT now(), attempts INT NOT NULL DEFAULT 0, max_attempts INT NOT NULL,
  state TEXT NOT NULL DEFAULT 'ready' CHECK (state IN ('ready','running','done','dead')),
  lease_until TIMESTAMPTZ, last_error TEXT NOT NULL DEFAULT '',
  traceparent TEXT NOT NULL DEFAULT '', causation_id TEXT NOT NULL DEFAULT '', hop_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), finished_at TIMESTAMPTZ);
CREATE UNIQUE INDEX IF NOT EXISTS besdk_job_queue_unique ON besdk_job_queue (kind, unique_key) WHERE unique_key IS NOT NULL AND state <> 'done';
CREATE INDEX IF NOT EXISTS besdk_job_queue_due ON besdk_job_queue (kind, run_at) WHERE state IN ('ready','running');
CREATE TABLE IF NOT EXISTS besdk_reconcile (name TEXT NOT NULL, item_id TEXT NOT NULL, attempts INT NOT NULL DEFAULT 0,
                                           next_at TIMESTAMPTZ NOT NULL DEFAULT now(), lease_until TIMESTAMPTZ, last_error TEXT NOT NULL DEFAULT '',
                                           PRIMARY KEY (name, item_id));

-- 快照回填进度
CREATE TABLE IF NOT EXISTS besdk_snapshot_sync (name TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT 'PENDING',
  cursor TEXT NOT NULL DEFAULT '', started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());

-- 授权投影（只在声明了 resources 的组件里建）
CREATE TABLE IF NOT EXISTS besdk_authz_acl (rtype TEXT NOT NULL, rid TEXT NOT NULL, relation TEXT NOT NULL, subject TEXT NOT NULL,
  expires_at TIMESTAMPTZ, revision BIGINT NOT NULL, PRIMARY KEY (rtype, rid, relation, subject));
CREATE INDEX IF NOT EXISTS besdk_authz_acl_subject ON besdk_authz_acl (rtype, subject, relation);
CREATE TABLE IF NOT EXISTS besdk_authz_cursor (scope TEXT PRIMARY KEY, revision BIGINT NOT NULL, rebuilt_at TIMESTAMPTZ);

-- 单据编号
CREATE TABLE IF NOT EXISTS besdk_number_series (series TEXT NOT NULL, scope TEXT NOT NULL DEFAULT '', period TEXT NOT NULL DEFAULT '',
  next_value BIGINT NOT NULL DEFAULT 1, gapless BOOLEAN NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (series, scope, period));

-- 可续跑的回填（foundations-data-platform §6.4）
CREATE TABLE IF NOT EXISTS besdk_backfill (name TEXT PRIMARY KEY, cursor TEXT NOT NULL DEFAULT '', done BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
```
