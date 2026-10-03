# SDK 重新设计：组件协议、黑盒一致性测试、三门官方 SDK 与迁移路径

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮，lane A）。只读调研，未改任何代码、未提交。
> 输入：同目录七份分析（`events-consistency`、`data-layer`、`identity-permissions`、`authz-architecture`、`data-lifecycle-v2`、`foundations-communication`、`foundations-data-platform`）、`../dept-scope-analysis.md`、`decisions.md`，以及**优先于一切分析的** `answers.md`；裁决 R38–R63（`.superpowers/sdd/plan-06b/takeover.md`、`progress.md`）。
> SDK 现状来自 be-sdk-go / be-sdk-python / be-sdk-ts 三个仓库 v0.5.0 的代码（行号以写作时工作区为准），外壳来自 `shell/be/*`，门禁来自 `tools/be-acceptance`，生成器来自 `tools/be-ops` v0.2.0。brickKit 只读了本机 v1.1.0 文档（`brickkit docs`）和源码仓库 `docs/en/`。
> 姊妹文件 `sdk-redesign-apis.md`：三门语言逐个 API、外壳启动器、夹具组件、第四门语言指南。本文件：结论、协议、一致性套件、现状盘点、迁移路径、brickKit 候选。
> **修订（phase A 收尾，lane X2）**：按控制者对九个 lane 报告的裁决（a…bc）和 R1 最小复现的结果（`../repros/README.md`）修订。be-protocol rc.1（`tools/be-protocol`）已经是规范正文，名字和说法不一致时以它为准，本文件只是设计记录。
> **修订（2026-10-03，lane L2b）**：吸收 brickKit v1.2–v1.3.1 的新能力（`brickkit-feedback/replies/phase-06.md`，控制者裁决 bk1–bk14，`.superpowers/sdd/plan-06b/bk13-rulings.md`）：族地址改为 `$endpoint:` 引用、每个 gRPC 端口一个键（不再 +1000）；密钥一律以文件交付（`mount: file`、`_FILE` 键、三门 SDK 都重读）；`readinessCheck`、`stopGracePeriodSeconds`、端口 `protocol`、`events:` 段进 `component.yaml`；`configSchema` 的协议键段和 `events:` 段由 be-ops 生成（O1）；边缘路由生成进部署条目；FR06-007 不做，0508 不变，协议加可选的"跑一次"入口。条款编号以 be-protocol 为准（L2a 同步修订）。
> **修订（2026-10-03，rc.2 spec lane 的文档 lane）**：按阶段 B 第一波审查裁决（`.superpowers/sdd/plan-06b/stageB-review.md`）定下的 rc.2 事实修订 §2、§4、§7：`be` 的 reason 从 32 行补齐到 36 个（新增 `REQUEST_INVALID`、`DEPENDENCY_UNAVAILABLE`、`REQUEST_CANCELLED`，补列 `NESTED_TX`）；路由判定顺序（先 401，再"还没拿到 bundle"的 503，再 stale / 撤销的授予 / 委托链）；空值即未设；`EVENTS_*` 没有目录默认值；`PG_POOL_MIN_IDLE` 退役；新键 `DEPLOY_ENV`；最后一次允许的投递照常 Nak、下一次收到时进 DLQ；payload 超过 64 KiB 必须拒绝；OpenAPI 标记 `x-be-permission` / `x-be-internal`；契约迁移靠会话 `application_name` 判断旧版本是否还在线；发版接 brickKit ≥ v1.4.0 的 `release.checks`（P20.5、§4.6），`compconf-record-scan` 收窄。be-protocol `v1.0.0-rc.2`、contract-infra-authz `v2.0.0-rc.2`、contract-infra-iam `v1.0.0-rc.2` 是这些事实的正文。

---

## 0. 结论（一页）

1. **用户唯一的要求（L1）：每个组件可以自由选语言。** 于是"规则"不能再住在某一门语言的 SDK 里。本设计把规则抽出来，叫 **组件协议 `be-protocol` 1.0**：在线协议、表结构、配置键这一层，定义一个组件要成为本项目合格成员必须做到的一切（§2，二十章）。三门 SDK 降为这份协议的**官方参考实现**。
2. **三样东西，各有一个家。**
   - **协议**：新仓库 `brickKit/be-protocol`。里面只有规范正文（英文为准、中文镜像）、JSON Schema、平台表参考 DDL、语义向量、夹具组件契约，**没有代码**。按 `MAJOR.MINOR` 版本化，minor 只增可选面（§3）。新建仓库要用户同意（§9 Q1）。
   - **黑盒一致性套件 `compconf`**：放在 `tools/be-acceptance/conformance/component/`（compconf 只作它的非正式简称）。对一个**运行中的容器**测，不看语言。套件自带假 IdP、假 authz、假对端和 OTLP 接收器，用真 PG 和真 JetStream。共 15 个 profile，按组件清单自动选用；结果写成测试记录。组件在 `component.yaml` 里声明 `release: {checks: [[make, conformance]]}`，`brickkit release`（brickKit ≥ v1.4.0）对发版提交跑一遍套件，不过就拒绝打 tag；`make gates` 的 `compconf-record-scan` 只对没声明这项检查的组件和外壳（别家的组件、去掉了检查的分叉）要求项目里存一份全绿记录（§4.6）。
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
| 17 | authz-architecture §5.4、foundations-communication §2.3 | 套件位置分别是 `be-acceptance/authzconf/`、`be-acceptance/conformance/<port>/` | 统一为 `tools/be-acceptance/conformance/<端口短名>/`（组件协议套件是 `component/`；`compconf`、`authzconf` 只作非正式简称）；**语义向量不放在任何套件里**：全协议通用的向量（money、幂等指纹、信封、日历、编号、错误、配置、脱敏……）放 be-protocol 的 `vectors/`；**族的判定向量**（authz 的范围求值等）以族契约仓库为准，放 `contracts/infra/authz/vectors/`，P6 按 tag 引用该仓库的 `EVALUATION.md`（K1 裁决 u） | 规范和向量必须同一个版本号；三门 SDK 从 be-protocol 的 tag 同步协议向量，从族契约仓库钉住的 tag 同步族向量 |
| 18 | data-lifecycle-v2 §4.14 | Go 路径 `be-sdk-go/v1/lifecycle` | `github.com/brickKit/be-sdk-go/lifecycle` | Go 的 v0 和 v1 都不带主版本后缀 |
| 19 | events-consistency、identity、data-layer | TS "不加"：事件、幂等、快照、库 | **全部加** | L1 |
| 20 | events-consistency §3.4、§5.3 | Python 的快照 / 幂等"等第一个用户再补" | 与 Go **同版本发布** | widget-py 必须过同一套 compconf；协议对等 |
| 21 | data-layer §0 | 外壳可以先用旧 SDK + INHERIT 组装 | 外壳在 SDK v0.6.x + NOINHERIT 上组装 | E11：全部在外壳之前做完 |
| 22 | foundations-communication §9.4 | Cron 时区配置键 `JOBS_TZ`，默认 UTC | 不加这个键。Cron 默认用 `BUSINESS_TIMEZONE`，每个任务可以写 `TZ` 覆盖 | 每日任务应按业务日历跑（F5） |
| 23 | foundations-data-platform §12.3 与 foundations-communication §5.4 | 两种错误体形状 | problem+json（RFC 9457）+ AIP-193 成员（§2 P4）。REST 上不再有 `error` 字段 | 一种形状；前端 06c 按 `domain:reason` 翻译 |
| 24 | foundations-communication §3.4 / §5.4 与 foundations-data-platform §2.4 | 池和出站舱壁满了，一说 `ResourceExhausted`，一说 `Unavailable` | 一律 `RESOURCE_EXHAUSTED` + `RetryInfo`，HTTP 映射为 429；reason 分开：池等待超时 `DB_POOL_EXHAUSTED`，出站舱壁满 `OUTBOUND_LIMIT`（与 foundations 15 一致） | 过载不该由服务配置自动重试（重试只针对 `UNAVAILABLE`）；与 R49 的 grpc-gateway 映射表一致 |
| 25 | foundations-data-platform §2.4 与 foundations-communication §3.2 T7 | 超时由角色级 `ALTER ROLE SET` 设，还是由 SDK `SET LOCAL` 设 | 两层都要：**SDK 每个事务 `SET LOCAL` 是保证**；be-ops 的角色级设置只兜底不走 SDK 的会话（psql、运维脚本） | 外壳里角色级设置不生效（T7） |
| 26 | foundations-communication §6.3 第 3 条与 data-lifecycle-v2 §4.7 | outbox 在线保留，一说 ≥ 30 天（作为回放的事实源），一说发布后 14 天 | **14 天**；更早的历史改走上游 `List` / 数据集 | 生命周期那一份更晚，并且考虑了擦除滞后（事件里有个人信息）；回放超过两周的事件，本来就该改成回填 |
| 27 | 本文 P2.10（rc.1）、0107 | 族地址手写成员服务名；族的 gRPC 地址 = `*_URL` 的端口 + 1000；`IAM_JWKS_URL` 单独一个键；门禁 `service-hostname-scan` 核对服务名 | `AUTHZ_URL`、`AUTHZ_GRPC_URL`、`IAM_URL`、`IAM_GRPC_URL` 四个键，在 `config/vars.yaml` 里写成 `$endpoint:<成员>[:grpc]`；JWKS 是 `{IAM_URL}/.well-known/jwks.json`，`IAM_JWKS_URL` 退役；`service-hostname-scan` 退役（bk1） | brickKit v1.2 的 `$endpoint:` 按 `brickkit.yaml` 算地址，跟着升级、外壳、本机运行走，放行 networkPolicy，不产生启动顺序、可以成环；端口算术是第二条隐藏约定 |
| 28 | 本文 P2.7 / P2.9（rc.1）、foundations 24 | 密钥经 `${VAR}` / `file://` 注入环境变量；运行期文件引用 `@file:/path` 是可选来源 | **每个 `secret: true` 键都以文件交付**：`mount: file`、名字以 `_FILE` 结尾、值是路径（`PG_PASSWORD_FILE`、`PG_OWNER_PASSWORD_FILE`、`S3_ACCESS_KEY_ID_FILE`、`S3_SECRET_ACCESS_KEY_FILE`、`APP_TOKEN_SIGNING_KEY_FILE`、`APP_TOKEN_NEXT_SIGNING_KEY_FILE`）；`_FILE` 后缀只留给密钥，所以 authz-static 的 `AUTHZ_POLICY_FILE` 改名 `AUTHZ_POLICY_PATH`；iam 签过名的公钥记在成员 schema 里供 JWKS 重叠，`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM` 退役；三门 SDK 用时读、比较修改时间和大小最多隔 30 s 重读；环境变量里没有任何密钥的值；`@file:` 取消（bk4） | brickKit v1.3 的 `mount: file`：Docker 只读目录挂载、K8s 投射卷，值变了 `up` 原地改写文件、不重启；Podman / SELinux 没测过 |
| 29 | 本文 P1.4、P1.6、§8 B3/B4 | `/readyz` 是 SHOULD、不接探针；停机宽限要等 brickKit | `/readyz` 是 MUST，`component.yaml` 声明 `readinessCheck`；`deployment.stopGracePeriodSeconds` 默认 30，`SHUTDOWN_GRACE` 默认 25 s、至少比它小 5 s；外壳自己声明，不小于成员的（bk2、bk3） | FR06-006、FR06-009 已在 brickKit v1.2 落地 |
| 30 | 本文 P12、§8 B11 | 事件的发布与订阅不向平台声明 | `component.yaml` 的 `events: {publishes, subscribes}` 由 be-ops 从事件契约和 `fixtures.yaml` 的 `events.consumes` 生成，门禁 `events-declaration-scan` 核对（bk5，P12.16） | FR06-005 已在 v1.3 落地，只用于 graph / deps / lint |
| 31 | 本文 §8 B1 | 请 brickKit 支持 configSchema 片段引用 | FR06-014 不做；be-ops 从 `config-keys.yaml` 按 profile **生成**每个组件 `configSchema` 的协议键段，门禁 `protocol-config-scan` 核对是最新的（bk11，O1） | 已发布的 `component.yaml` 必须自己说完自己 |
| 32 | foundations 18、§7.8 | 边缘路由由 be-ops 生成一张中立路由表，再渲染成 Traefik file provider 和 be-ops 自己写的 Ingress | 生成进部署条目：K8s 写 `paths`（brickKit 每组件一份 Ingress、按路径段匹配）；Docker / Podman 写 Traefik 路由 `labels`（`PathRegexp` 以路径段为界，Traefik 接在项目 `network:` 上；引擎是 Docker 29 时要 Traefik ≥ 3.6，3.3.7 请求的 API 版本被 Docker Engine 29 拒绝，取代原先的"≥ 3.2"）；外壳成员的 router 同时写在外壳条目上（bk7、bk8、bk14）。路由级超时在 Traefik 上只能经 file provider 的 `serversTransport` 表达，标签设不了（foundations 18） | FR06-015、FR06-019、FR06-021 已落地；brickKit 在 Docker 上按设计不生成网关 |
| 33 | 0508、§8 | — | FR06-007（平台定时任务）不做，0508 不变；协议加可选能力"跑一次就退出"（`<entrypoint> job run <name>`，P14.8），走同一批租约 / 时间槽表，外部触发（宿主机 cron + `docker compose run --rm --no-deps`，或不带 `brickkit.io/project` 标签的手写 CronJob），`JOBS_OVERRIDES` 关掉进程内那一份（bk9） | brickKit 的建议做法；只在"移出外壳"经测量仍不够之后用 |
| 34 | 本文 §4.6、§8 B14 | "先有 compconf 报告再打 tag"只靠 `version-bump-ship` 技能约束；`compconf-record-scan` 要求 `brickkit.yaml` 里每个组件和外壳都有报告 | 组件和外壳在 `component.yaml` 声明 `release: {checks: [[make, conformance]]}`（P20.5，brickKit ≥ v1.4.0）：`brickkit release`（以及 `publish`、`release --local`）对发版提交跑套件，失败就拒绝打 tag（`RELEASE_CHECK_FAILED`），`--skip-checks` 会被打印出来。`compconf-record-scan` 保留但收窄：只对钉住版本的清单里**没有**这项检查的组件或外壳要求项目里存一份全绿报告 | FR06-028 在 brickKit v1.4.0 落地；门禁只守 `release.checks` 管不到的东西：项目自己不发版的组件 |
| 35 | 本文 §2（rc.1） | 三门 SDK 各自实现时出现的分歧（reason 名、判定顺序、空串、最后一次投递、`EVENTS_*` 默认值……） | 统一成 be-protocol rc.2，见本文开头的修订说明和 §2 各条 | 阶段 B 第一波审查裁决；向量和三门 SDK 以 rc.2 为准 |

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
| P1.1 | 镜像有两个入口：默认命令起服务；`component.yaml` 的 `migration.command` 跑迁移，退出 0 表示成功。迁移用同一个镜像、同一份配置，每次 `up` 都会重跑，所以必须幂等（P11）。官方 SDK 的约定是同一个二进制带子命令：`[./component]` 起服务；`migrate up` / `migrate down <n>` / `migrate status` 迁移（`component.yaml` 写 `[./component, migrate, up]`）；提供时还有 `job run <name>`（P14.8）。入口不认识的参数、不存在的任务名，在读配置之前立刻以 **64** 退出，拼错的迁移命令永远不会变成第二个服务进程；环境里根本没有 `COMPONENT_ID`（进程不是平台启动的）同样立刻以 64 退出（CP-CORE-01） | MUST |
| P1.2 | 启动顺序固定：读配置并校验 → 开端口 → **在后台**连接 PG、总线、authz、JWKS。配置缺必填项或类型错，打一行 JSON 日志点名是哪个键，以退出码 **78**（EX_CONFIG）退出；`COMPONENT_ID` 有、但和镜像里的组件 ID 不同，也是 78。依赖暂时不可达，就退避重试，**不退出**（CP-CORE-02、03） | MUST |
| P1.3 | `GET`/`HEAD /healthz` 只回答"进程活着"：返回 200，不碰 PG、总线、authz 或任何依赖（CP-CORE-04：套件停掉 PG 后它仍是 200） | MUST |
| P1.4 | `GET /readyz`：首次拿到 bundle、库身份探测通过（P10.7）、库里的迁移版本等于镜像的迁移版本，三者都满足时答 200；否则答 503，body 是 problem+json，`reason` 为 `NOT_READY` 并附 `metadata.waiting`。条件一旦满足就锁定：之后 PG、总线、authz 或别的组件暂时不可用，都不会让它变回 503（bundle 按 fail-static 保留），所以下游抖动不会把所有副本一起摘掉。平台经 `readinessCheck`（P1.11）探它（CP-CORE-05） | MUST |
| P1.5 | 还没拿到过 bundle 时，**每个非 Public 路由**（Authenticated 的也一样）答 503 + `AUTHZ_NOT_READY`；但先验 token，缺失或无效仍先答 401 `TOKEN_INVALID`（判定顺序见 P6.2）。Public 路由照常服务（CP-AUTH-10） | MUST |
| P1.6 | 收到 SIGTERM：先停止接新请求；在途请求在 `SHUTDOWN_GRACE`（默认 25 s）内完成；再停后台工作，释放租约、对在途消息 ack 或 nak、把 outbox 当前批次收尾；最后退出 0。整个过程落在平台的停机宽限期（P1.12）之内，平台从不需要强杀（CP-CORE-06） | MUST |
| P1.7 | 可恢复的错误永不退出进程。所有后台工作都受监督：panic 被恢复，按 1 s → 5 min 退避重启，一个任务退出不影响其它任务。外壳和单跑行为完全相同（CP-JOBS-05、CP-SHELL-06） | MUST |
| P1.8 | 致命错误一律以**非 0** 退出：配置非法；库里的迁移版本高于镜像（迁移入口已经 WARN，服务入口拒绝启动）；外壳成员声明与编译进来的不一致。**不允许 `Start` 出错后以 0 退出**（今天的 Go 就是这样，§6.2 #37） | MUST |
| P1.9 | 镜像里有 `/bin/sh` 和 `wget`，因为健康检查经 shell 执行（现有易错点）（CP-CORE-07） | MUST |
| P1.11 | `component.yaml` 声明两个检查，brickKit（≥ v1.3.1）把它们变成引擎的探针：`healthCheck: {type: http, path: /healthz}`（存活与启动）和 `readinessCheck: {type: http, path: /readyz}`（就绪）。K8s 上就绪探针决定 Pod 何时收流量；Docker / Podman 上 compose 的健康检查探 `/readyz`，依赖方等它就绪才启动（CP-CORE-12） | MUST |
| P1.12 | `component.yaml` 声明 `deployment.stopGracePeriodSeconds`：默认 **30**，始终 ≥ `SHUTDOWN_GRACE` + 5 s。brickKit 写成 compose 的 `stop_grace_period` 和 K8s 的 `terminationGracePeriodSeconds`；部署条目可以覆盖，保持同样的余量。外壳声明自己的值（P19）（CP-CORE-06、12） | MUST |
| P1.13 | 每个端口都监听所有接口，IPv4 和 IPv6（`0.0.0.0` 和 `::`，或一个双栈 `::`）：平台的健康检查在容器里探 `127.0.0.1`（brickKit v1.3 起不再探 `localhost`，因为 Alpine 会解析成 `::1`），K8s 探 Pod IP（CP-CORE-13） | MUST |

### P2 配置

| # | 规则 | 等级 |
|---|---|---|
| P2.1 | 配置**只**来自平台注入：单跑时是进程环境，外壳里是本成员那一项的 `config`。键名就是环境变量名（brickKit 环境变量契约） | MUST |
| P2.2 | 组件只读自己 `configSchema` 里声明过的键，加上平台保留名（`COMPONENT_ID`、`COMPONENT_VERSION`、`*_ENDPOINT`、`PORT`）。官方 SDK 启动时读镜像里的 `component.yaml`，把 `Config` 限制在声明过的键上，读没声明的键直接报错 | MUST（INTERNAL 部分：只读声明的键） |
| P2.3 | 类型严格：整数、布尔、时长（Go duration 语法，如 `5s`、`15m`）、URL、JSON（结构化键）。布尔只认 `true`、`false`、`1`、`0`（区分大小写）。值有、但解析不了，就当配置错误（P1.2），不静默回退到默认值。**空值对每种类型都等于没设**，字符串也一样：有默认值就取默认值，必填键就是缺失（78）（向量 `empty-string-is-absent`、`empty-string-required`，取代 rc.1 的 `empty-string-is-value`）。`one_of` 的一组键（`EVENT_BUS_URL`、`NATS_URL`）至少要设一个（CP-CORE-02） | MUST |
| P2.4 | 不使用保留名做配置键，也不以 `_ENDPOINT` 结尾（brickKit 规则） | MUST |
| P2.5 | 可选依赖没装时，它的 `*_ENDPOINT` 变量**根本不存在**（不是空串）。组件必须降级，不能崩溃 | MUST |
| P2.6 | 读依赖地址时去掉 `http://` 和末尾的 `/`；gRPC 一律用带端口名的变量（`<DEP>_GRPC_ENDPOINT`）。槽位族没有这类变量，经它自己的地址键访问（P2.10） | MUST |
| P2.7 | 声明了 `secret: true` 的键**以文件交付**，从不作为环境变量的值：声明 `mount: file`、名字以 `_FILE` 结尾（P2.12），变量里是 brickKit 挂载的文件路径 `/run/brickkit/secrets/<带版本的服务名>/<KEY>`（`mode: local` / `debug` 时是宿主机路径；外壳里成员那一项带同一个路径）。项目配置里它的值只写 `${VAR}`、`file://` 或 K8s 上的 `existingSecret`。密钥的值不出现在环境变量、日志、错误体、`/_be/info` 和指标标签里（CP-OBS-04、CP-CORE-14） | MUST |
| P2.8 | 组件在 `configSchema` 里声明它用到的 profile 需要的全部协议键，类型、`secret`、`mount` 和默认值按目录写。这一段由 be-ops 按 `config-keys.yaml` **生成**（brickKit 不做片段引用，FR06-014），门禁 `protocol-config-scan` 核对它是最新的。组件对它用到的每个 profile **手写一个触发键**，be-ops 据此补齐整块：`db` 的触发键是 `PG_SCHEMA` 或 `PG_HOST`，`blob` 是 `S3_BUCKET` 或 `S3_URL`（README 的 Conformance 一节和 `conformance-cases.yaml` 用同一条规则，§4.3） | MUST |
| P2.9 | 密钥在用的时候从文件读，文件变了就重读：比较修改时间和大小，两次比较最多相隔 30 s（文件系统监视可以更早），从不为此重启，每次变化记一条点名键的 INFO。文本密钥去掉恰好一个结尾 LF 或 CRLF；组件自己的二进制密钥逐字节交出。新值不重启就生效：数据库口令对变化之后新开的连接生效（旧连接活到 `PG_CONN_MAX_LIFETIME`）；对象存储的凭据成对重读；签名私钥靠 JWKS 的新旧重叠轮换。变化之后读失败时保留上一个有效值，记 ERROR，计 `be_secret_reload_failures_total`。三门 SDK 一样实现（apis §1 第 7 条、§2.2） | MUST |
| P2.10 | 槽位族地址：已安装的族成员只经族的地址键访问，从不建依赖边：授权族 `AUTHZ_URL`、`AUTHZ_GRPC_URL`，身份族 `IAM_URL`、`IAM_GRPC_URL`。项目在 `config/vars.yaml` 里各写一次 brickKit `$endpoint:` 引用（`AUTHZ_URL: $endpoint:infra/authz`、`AUTHZ_GRPC_URL: $endpoint:infra/authz:grpc`），组件以 `$var:` 取用；换成员每个键改一行。值是 `http://<host>:<port>`，不带路径和末尾 `/`；REST 路径接在 `*_URL` 后面，`*_GRPC_URL` 去掉 scheme 当拨号目标。**不做端口算术**（取代 rc.1 的"+ 1000"） | MUST |
| P2.12 | 密钥声明：`configSchema` 里一项是 `secret: true`，当且仅当它声明了 `mount: file`，当且仅当它的名字以 `_FILE` 结尾；协议键和组件自己的键一样。其它键都不以 `_FILE` 结尾（CP-CORE-14，门禁 `protocol-config-scan`） | MUST |

**协议级配置键**（组件按自己用到的 profile 写进 `configSchema`，这一段由 be-ops 生成；be-protocol 发布一份 `schemas/config-keys.yaml`，门禁 `protocol-config-scan` 按它核对，§7.3。名字和默认值以该文件为准。每个键另有 `shell: process | member`：`process` 是整个外壳进程一个值，从外壳自己的配置读，如 `PG_HOST`、`PG_PORT`、`PG_DATABASE`、`PG_MIGRATION_*`、`EVENT_BUS_URL`、`NATS_URL`、`OTEL_BASE_URL`、`DEPLOY_ENV`、`SHUTDOWN_GRACE`；`member` 是每个成员各取自己的值。be-ops 据此生成外壳的键集合，P19.3）：

| 键 | 谁要 | 必填 | 默认 | 含义 |
|---|---|---|---|---|
| `PG_HOST` `PG_PORT` `PG_DATABASE` | 有库 | 是（PORT 否） | `5432` | 共享变量 |
| `PG_USER` `PG_PASSWORD_FILE` | 有库 | 是 | — | **运行角色**：只有 DML，不是属主角色的成员；服务的登录角色，也是每个运行期事务 `SET LOCAL ROLE` 的目标（R63、F27）；口令是密钥，以文件交付，每建一条新连接读一次 |
| `PG_OWNER_USER` `PG_OWNER_PASSWORD_FILE` | 有库 | 是 | — | **属主角色**：拥有本组件的表、做 DDL，只给迁移步骤（含平台迁移）登录用（P10.12、P11.1）；名字和口令都来自配置，不写字面量（R63）；口令是密钥，以文件交付。已知限制：brickKit 给迁移容器的环境和挂载与服务相同（`05-migration/02`），所以运行容器里也有这个口令文件，SDK 运行期**从不读它**；brickKit 不做 FR06-013（迁移专用的环境覆盖），这条限制是永久的 |
| `PG_SCHEMA` | 有库 | 是 | **无默认** | 不从角色推，也不在代码里写默认值；最长 40 个字符（P10.1） |
| `PG_POOL_MAX` | 有库 | 否 | `10` | 单跑时是池上限；外壳里是本成员在共享池里的并发预算（P10.5） |
| `PG_POOL_ACQUIRE_TIMEOUT` | 有库 | 否 | `5s` | 取连接的等待上限，超时答 `RESOURCE_EXHAUSTED`/`DB_POOL_EXHAUSTED` |
| `PG_CONN_MAX_LIFETIME` `PG_CONN_MAX_IDLE_TIME` | 有库 | 否 | `30m` / `5m` | — |
| `PG_MIGRATION_HOST` `PG_MIGRATION_PORT` | 有库 | 否 | 同 `PG_HOST` / `PG_PORT` | 用了 transaction 模式的 pooler 时，迁移要直连库。这正是 brickKit 答 FR06-013 时推荐的做法：组件自己声明、只由迁移命令读的键 |
| `EVENT_BUS_URL` | 发或收事件 | 否 | 回退 `NATS_URL` | scheme 选适配器：`nats://`、`postgres://…?schema=be_bus`；`kafka://` 预留 |
| `NATS_URL` | 同上 | 与 `EVENT_BUS_URL` 至少设一个（`one_of`） | — | 共享变量 |
| `EVENTS_MAX_DELIVER` `EVENTS_BACKOFF` | 收事件 | 否 | **无**（目录里不给默认值） | 部署层面的调优；"设了"指配置里有这个键（P2.3：空值等于没设）。优先级：键（设了时）> 订阅自己的值 > 内置的 `8` / `1s,10s,1m,5m,15m,30m,1h`；compconf 用它把重投缩短。两者都由 **SDK** 执行，不写进服务端 consumer（R1 #7，裁决 ax）：`EVENTS_BACKOFF` 是 handler 失败后 `NakWithDelay` 的延迟表，`EVENTS_MAX_DELIVER` 是 SDK 写 DLQ 的门槛（P12.5、P12.7），改了立刻生效、不需要更新 durable |
| `AUTHZ_URL` | 有受保护路由 | 是 | — | authz 族成员的 REST 基础地址；`config/vars.yaml` 里写 `$endpoint:infra/authz`（0107）；取代 `AUTHZ_BUNDLE_URL` |
| `AUTHZ_GRPC_URL` | 调 `infra.authz.v2.AuthzProvider`（可共享资源的属主 WriteTuples、调 Check / ListObjects 的、身份成员调 ResolveClaims） | 是 | — | 同一成员名为 `grpc` 的端口：`$endpoint:infra/authz:grpc`；拨号目标是去掉 `http://` 的值 |
| `IAM_URL` | 有受保护路由 | 是 | — | iam 族成员的 REST 基础地址：`$endpoint:infra/iam-casdoor`；JWKS 在 `{IAM_URL}/.well-known/jwks.json`（P5.4），`IAM_JWKS_URL` 退役；永远不建依赖边 |
| `IAM_GRPC_URL` | 调 `infra.iam.v1.IamProvider`（BatchGetUsers 等） | 否 | — | `$endpoint:infra/iam-casdoor:grpc`；没有时这些读取降级 |
| `IAM_ISSUER` | 有受保护路由 | 是 | — | `iss` 的期望值，是稳定的名字 `urn:be:<TENANT_ID>:iam`，不是地址，换成员也不变（K2） |
| `TENANT_ID` | 同上 | 是 | — | `aud` 的期望值（F1：一个部署就是一个租户） |
| `BOOTSTRAP_ADMIN_LOGIN` | iam 族成员 | 否 | — | 第一个管理员的 IdP 登录名或邮箱（共享变量）。平台 `sub` 由 iam 成员签发、首次登录前不可知，所以不再用 `BOOTSTRAP_ADMIN_SUB`：成员在此人首次登录时把它绑到平台 `sub`，发带 `bootstrap_admin: true` 的目录事件，authz 成员据此授予管理员角色（裁决 r、ai） |
| `BUSINESS_TIMEZONE` | 用 Cron | 否 | `Asia/Shanghai` | 部署级默认时区，Cron 按它求值（F5）；法人自己的时区来自 mdm/org（P11.9） |
| `DATA_LIFECYCLE` | 有库 | 否 | `mode: on`，适配器都是 `none` | data-lifecycle-v2 §4.3 |
| `S3_URL` `S3_REGION` `S3_FORCE_PATH_STYLE` `S3_BUCKET` | 用对象存储 | 视情况 | — / `us-east-1` / `false` | foundations-data-platform §8.2 |
| `S3_PUBLIC_URL` | 用对象存储 | 否 | 同 `S3_URL` | 浏览器用的地址；预签名 URL 按它签（P17.2） |
| `S3_ACCESS_KEY_ID_FILE` `S3_SECRET_ACCESS_KEY_FILE` | 同上 | 视情况 | — | 每个组件一套；密钥，以文件交付，成对重读 |
| `OTEL_BASE_URL` | 全部 | 否 | 空 = 不导出 | OTLP/HTTP 的基础地址，SDK 自己补 `/v1/traces` |
| `DEPLOY_ENV` | 全部（profile `obs`，共享） | 否 | `dev` | 部署环境的名字（`dev`、`test`、`staging`、`prod`……），导出为 resource 属性 `deployment.environment.name`（P18.1） |
| `DEFAULT_LOCALE` | 全部 | 否 | `zh-CN` | 部署的默认语言：problem 体的 `title` / `detail` 用它（P4.1）。只用目录里有的语言：主语言子标签是 `zh` 或 `en` 就选那种文案，其它值回落到 `en`，启动时记一条 WARN（不以 78 退出） |
| `LOG_LEVEL` | 全部 | 否 | `info` | `debug` / `info` / `warn` / `error` |
| `HTTP_DEFAULT_TIMEOUT` | 有 HTTP 路由 | 否 | `10s` | 入站默认截止时间（F13），路由可以自己声明 |
| `GRPC_MAX_CONNECTION_AGE` | 有 gRPC 端口 | 否 | `5m` | compconf 会把它缩短 |
| `SHUTDOWN_GRACE` | 全部 | 否 | `25s` | 至少比 `deployment.stopGracePeriodSeconds`（默认 30）小 5 s（P1.12） |
| `JOBS_OVERRIDES` | 有库 | 否 | 空 | JSON，按任务名覆盖 `interval` / `cron` / `enabled`；运维调优用，compconf 也用它把平台任务调快 |

`PG_POOL_MIN_IDLE` 从目录里退役（列在 `config-keys.yaml` 的 `retired` 下）：保持多少空闲连接是每个运行时自己连接池的行为，由各 SDK 的文档写明（Go pgxpool、Python asyncpg 的 `min_size`、TS pg-pool）；契约迁移门禁要求的"每个成员至少一条在线会话"见 P11.4。

brickKit 的 `config-schema-design` 一节提醒过："一个键装一整块 JSON"属于拆得太粗。`DATA_LIFECYCLE` 是有意的例外：它是结构化的声明，拆成平铺的键会多出几十个，而且没法表达"按表"。（法人日历不走配置：P2 答复后由 mdm/org 提供，见 P11.9。）这一点在 foundations 文档里写明。

### P3 HTTP 面（用户面 REST 与运维端点）

| # | 规则 | 等级 |
|---|---|---|
| P3.1 | 主端口（`deployment.port`）上的路径分三类，此外没有别的：用户面 `/{domain}/{name}/…`（经边缘路由，见 `edge_routes`）；运维面 `/healthz`、`/readyz`、`/metrics`、`/_be/info`（不进边缘）；资源契约 `/{domain}/{name}/_authz/*`、`/_shares/*`、`/_lifecycle/*`（经边缘，P6、P16）。BFF 例外，它的用户面是 `/graphql` | MUST |
| P3.2 | 请求 ID：入站带 `X-Request-Id` 就沿用（客户端伪造的那一份由边缘剥掉）；没有就用 trace-id。响应一律回写 `X-Request-Id`；所有出站调用都带上它（CP-CORE-10） | MUST |
| P3.3 | trace：入站提取 W3C `traceparent` 和 `baggage`；本次请求的 span 是它的子 span（CP-OBS-01） | MUST |
| P3.4 | 截止时间：每个路由有一个截止时间。默认取 `HTTP_DEFAULT_TIMEOUT`（10 s）；编排类路由声明 15 s；导出走异步，不占同步路由（F13）。到点答 504 + `DEADLINE_EXCEEDED`，同时取消下游调用和事务（CP-OUT-07、CP-DB-02；原先单列的"超时"用例不再单设，be-protocol rc.1 已删） | MUST |
| P3.5 | 服务端超时：读请求头 5 s，读整个请求 30 s，写响应取"路由截止时间 + 5 s"，空闲连接 120 s。慢速请求头必须被断开（CP-CORE-08）。TS 上 Node 只按 `connectionsCheckingInterval` 的周期检查这两个超时（默认 30 s），SDK 必须把它设成 1 s（R1 #8，apis §4） | MUST |
| P3.6 | 请求体上限默认 1 MiB，路由可以声明更大（与 foundations 16 一致），超了答 413 + `BODY_TOO_LARGE`。这个 413 **可以**在守卫之前（鉴权之前）答出，它的访问日志行不受 P18.4 的 `sub` / `perm` 约束；套件发超大请求体时带 `Expect: 100-continue` 并重试。上传一律走对象存储的预签名 URL（CP-CORE-09） | MUST |
| P3.7 | 写命令的幂等键可以放在 `Idempotency-Key` 请求头里，也可以放在 body 的 `idempotency_key` 字段里，两者等价；同时出现且取值不同，答 400（P13） | MUST |
| P3.8 | 列表分页用游标（0301，对齐 AIP-158）：参数 `page_size`（有上限，默认 50，最大 500；超过上限就降到上限）、`cursor`，返回 `next_cursor`（到末尾为空）。游标不透明，里面编码了排序键、最后一个 ID 和过滤条件的哈希；换了过滤条件还用旧游标，答 400 + `CURSOR_INVALID`。不返回精确总数 | MUST |
| P3.9 | 派生视图（投影、快照、ACL）的 List / Get 响应带 `X-Data-As-Of`，值是这份投影最近处理完的事件的 `occurred_at`（RFC 3339）（foundations-communication §4.6） | SHOULD |
| P3.10 | 访问日志：用户面和资源契约上的每个请求一行，`msg = http_request`，字段见 P18.2，级别见 P4.6。运维端点（`/healthz`、`/readyz`、`/metrics`、`/_be/info`）不在此列，运行时**可以**按 debug 记它们 | MUST |
| P3.11 | 不写 CORS。默认同源，由边缘负责 | MUST |
| P3.12 | `/metrics` 是 Prometheus 文本格式（P18.3）；`/_be/info` 见 P20 | MUST |
| P3.13 | 路由自己的截止时间和请求体上限，在它的 OpenAPI operation 上声明为 `x-be-deadline-seconds`（整数）和 `x-be-max-body-bytes`（整数），边缘、服务端和前端读的是同一个数字；没写就是 P3.4、P3.6 的默认值 | MUST |
| P3.16 | OpenAPI operation 标记：每个 operation 声明 `x-be-permission`，值是一个权限键、`authenticated` 或 `public`（Public 就写 `x-be-permission: public`）。**缺了 `x-be-permission` 永远不算声明过守卫**（fail closed）：选 profile 时把它当受保护的（`auth` 适用），门禁拒收这份契约；**唯一的例外**是标了 `x-be-internal: true` 的 operation：提供方平面或运维端点上只给系统流量用的（authz 的 `/authz/v2/*`、iam 的 `/.well-known/*`），不是用户流量，边缘从不路由它，不计入边缘路由覆盖率，也**不需要** `x-be-permission`（更正 rc.2 初稿的"仍声明"）。两个族契约的 OpenAPI 都带这两个标记（iam 原先的 `x-guard` / `x-edge` 改名） | MUST |

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
| P4.1 | 组件的每个 4xx/5xx 都是这个形状。`reason` 是 UPPER_SNAKE。`domain` 就是组件 ID，原样不变（`erp/inventory`），`type` 是 `urn:be:<domain>:<reason>`；SDK 自己的 reason 用 `domain: "be"`。**例外**：槽位族的成员用族的 ID 代替自己的 ID（每个授权成员都答 `domain: "infra/authz"`），前端每个族只需一张表（K1 裁决 x）。`title` / `detail` 按 `DEFAULT_LOCALE` 写（CP-ERR-01） | MUST |
| P4.2 | gRPC 上：标准状态码 + `google.rpc.ErrorInfo{reason, domain, metadata}`，按需再附 `BadRequest`、`PreconditionFailure`、`RetryInfo`、`ResourceInfo`。REST 与 gRPC 之间按 grpc-gateway 的表互相映射（R49：InvalidArgument / FailedPrecondition / OutOfRange → 400，AlreadyExists / Aborted → 409，NotFound → 404，ResourceExhausted → 429，Unavailable → 503，DeadlineExceeded → 504）（CP-ERR-02） | MUST |
| P4.3 | `INTERNAL`、`UNKNOWN`、`DATA_LOSS` 一律只返回一句通用文案 + `trace_id`，原始错误只进日志。SQL 错误、栈、token 解析失败的原文都不进响应（CP-ERR-03） | MUST |
| P4.4 | 每个组件在 `contracts/errors.yaml` 登记自己的 reason，字段是 `{reason, code, http, params[], title: {zh, en}, message: {zh, en}, since, deprecated}`（与 foundations 15 一致）。只增不改，规则同 `permissions.tsv`。前端用它生成 i18n 文案表，服务端不翻译 | MUST |
| P4.5 | GraphQL（BFF）：`errors[].extensions = {code, reason, domain, metadata, request_id, trace_id}`（与 foundations 15 一致） | MUST |
| P4.6 | 日志级别按状态码定（R51）：Internal / Unknown / DataLoss 记 ERROR；Unavailable / DeadlineExceeded 记 WARN；Cancelled 永不当错误记；调用方错误记 INFO。**访问日志行的级别按同一张表**：500（INTERNAL / UNKNOWN / DATA_LOSS）是 error；503 / 504（UNAVAILABLE / DEADLINE_EXCEEDED）是 warn；其余（2xx、3xx、4xx、499、501）是 info（向量 `errors/levels` 的 `access_log_level`） | MUST |

**保留的 SDK reason**（`domain: be`，be-protocol 的 `schemas/errors-be.yaml`）。下表与 foundations 15 的平台 reason 表、与 `errors-be.yaml`、与 spec/04 逐行相同，共 **36** 个（两份文档的并集，再加边缘自己产生的三个 `RATE_LIMITED` / `UPSTREAM_UNAVAILABLE` / `UPSTREAM_TIMEOUT`，S-b 裁决 ap 的 `NETWORK_IN_TX`、`DB_TOO_MANY_CONNECTIONS`，rc.1 的 `NESTED_TX`，以及 rc.2 的 `REQUEST_INVALID`、`DEPENDENCY_UNAVAILABLE`、`REQUEST_CANCELLED`；运行时自己答出的每个非 OK 回答都有 reason，所以取消永远不会变成 INTERNAL / 500；一个含义一个名字：池等待超时是 `DB_POOL_EXHAUSTED`、出站舱壁满是 `OUTBOUND_LIMIT`，不再有 `BULKHEAD_FULL`；缺功能键是 `MISSING_PERMISSION`；游标不匹配是 `CURSOR_INVALID`；重试用尽的事务冲突是 `TX_CONFLICT`）：

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
| `OUT_OF_SCOPE` | `PERMISSION_DENIED` | 调用方持有路由键，但这条记录不在这个键的范围内；或请求参数本身就是一个维度取值，且不在调用方的范围内（`warehouse_id=7`）（K1 裁决 w） |
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
| `RATE_LIMITED` | `RESOURCE_EXHAUSTED` | 边缘按客户端 IP（以后按 API key）限流；HTTP 429，带 `Retry-After` |
| `UPSTREAM_UNAVAILABLE` | `UNAVAILABLE` | 边缘找不到或连不上后端；HTTP 502 / 503。**只由边缘产生**，运行时自己不用它 |
| `UPSTREAM_TIMEOUT` | `DEADLINE_EXCEEDED` | 后端没有在边缘超时内答复；HTTP 504。只由边缘产生 |
| `NETWORK_IN_TX` | `INTERNAL` | 事务里发起了网络调用（P8.4）；编程错误，日志和测试运行里点名这个 reason，调用方按 P4.3 仍只看到 `INTERNAL` 的通用文案 |
| `DB_TOO_MANY_CONNECTIONS` | `UNAVAILABLE` | PostgreSQL 拒绝新连接（SQLSTATE `53300`） |
| `NESTED_TX` | `INTERNAL` | 同一个执行流在事务里又开事务（P10.6）；编程错误，只进日志，调用方看到 `INTERNAL` 的通用文案 |
| `REQUEST_INVALID` | `INVALID_ARGUMENT` | 请求解不开，或不符合这个操作的 schema：JSON 格式错、类型错、缺必填字段、未知的枚举值、路径或查询参数形状不对（如坏的 UUID）、格式错误的十进制字符串（P11.6）。字段错误放在 `violations`（gRPC 是 `BadRequest`）。由运行时的请求解码和组件自己的形状校验抛出；HTTP 400（TS 原先的 `MALFORMED_REQUEST` 改名为它） |
| `DEPENDENCY_UNAVAILABLE` | `UNAVAILABLE` | 运行时连不上这个请求需要的东西；HTTP 503，参数 `dependency`：`metadata.dependency` 是 `db`（PostgreSQL 连不上、连接断开、SQLSTATE 类 `08`、`57P01`、`57P02`、`57P03`）、`bus`（事件总线，直接发布时）、`blob`（对象存储），或者没有答复的依赖的组件 ID / 槽位族 ID（连接被拒、被重置，或答了 UNAVAILABLE 但没带自己的 ErrorInfo）。答了自己 ErrorInfo 的依赖原样转发（P4.9）。取代 Go 提议的 `DB_UNAVAILABLE` 和 TS store 对 `UPSTREAM_UNAVAILABLE` 的借用；`53300` 仍是 `DB_TOO_MANY_CONNECTIONS` |
| `REQUEST_CANCELLED` | `CANCELLED` | 调用方取消了请求（客户端断开连接、gRPC 客户端取消），包括这种取消引起的 SQLSTATE `57014`；HTTP 499。永不当错误记（P4.6），访问日志行是 info |

### P5 身份：JWT 验证

| # | 规则 | 等级 |
|---|---|---|
| P5.1 | 请求头写法是 `Authorization: Bearer <jwt>`。缺失或格式不对，答 401 `TOKEN_INVALID`（CP-AUTH-01） | MUST |
| P5.2 | `alg` 只接受白名单里的 `RS256`、`ES256`、`EdDSA`，而且必须等于 JWKS 里那把钥匙的 `alg`。`kid` 必填（CP-AUTH-02） | MUST |
| P5.3 | 必填的 claim：`iss` 等于 `IAM_ISSUER`；`aud` 包含 `TENANT_ID`；`typ` 等于 `"access"`，`refresh` 和缺失一律拒收；`sub` 非空；`exp`、`iat`、`jti` 都有；有 `nbf` 时检查。时钟偏差容忍 60 s（CP-AUTH-03…06：刷新令牌、错的 iss、错的 aud、没有 exp，各一条） | MUST |
| P5.4 | JWKS：本地缓存，最长 1 h；遇到不认识的 `kid` 时刷新一次，最多每 30 s 一次（这个限制不管启动时的首次拉取和每小时的例行刷新）；拉取超时 3 s；拉取失败沿用旧钥匙（fail-static）。轮换期间新旧两把钥匙签的 token 都能验过（CP-AUTH-07） | MUST |
| P5.5 | 认识的 claim 包括 `sub`、`tenant_id`、`roles[]`、`dept_path`、`act{sub, kind, act}`、`ceil[]`、`dg`、`azp`、`locale`。`org_id` 弃用，读但不用。委托 token（带 `act`、非空的 `ceil` 或非空的 `dg`）要求 bundle 能力 `delegation`；`act` 链上每一环：`kind: agent` 还要 `agents`（A4：只占位），`kind: user`（代人登录）还要 `impersonation`，`kind: svc` 不再要别的；缺了就答 401 `UNSUPPORTED_DELEGATION`。这些检查排在 stale 之后（P6.2，authz E2 为准） | MUST |
| P5.6 | stale：`iat` 早于 `stale_since[sub]` 减 5 s，答 401，带响应头 `WWW-Authenticate: Bearer error="token_stale"`，`reason` 为 `TOKEN_STALE`；token 的 `dg` 在 bundle 的 `revoked_grants` 里（授予已撤销）也答 401 `TOKEN_STALE`（CP-AUTH-08） | MUST |
| P5.7 | 服务账号的 `sub` 写成 `svc:<id>`，带角色，走和用户相同的判定（扩展点，现在没有签发方） | MUST（会读） |
| P5.8 | 原始 token 只存在请求上下文的私有槽里，供 `UserHTTP` 转发；不进 `User` 对象，不进日志 | INTERNAL |

### P6 授权：bundle、范围、资源契约、投影

provider 契约（bundle v2、changes、Check、WriteTuples）归族契约仓库 `contract-infra-authz`（authz-architecture §3）。本章只规定**组件一侧**怎么消费它、怎么求值、对外挂出什么。求值语义按 tag 引用该仓库的 `EVALUATION.md`，判定向量也以该仓库的 `vectors/` 为准，be-protocol 不另存一份（K1 裁决 u）。

| # | 规则 | 等级 |
|---|---|---|
| P6.1 | bundle：`GET {AUTHZ_URL}/authz/v2/bundle`，带 `If-None-Match` / ETag。每 15 s 轮询一次；首次拉取失败按 0.5 s 起步、翻倍、上限 15 s 退避；单次超时 3 s；收到 `infra.authz.changed.v1` 的 poke 立刻拉一次；拉取失败沿用旧 bundle（fail-static）。`contract` 不是 `authz/2.*` 时拒绝使用，并记 ERROR | MUST |
| P6.2 | 路由判定链（与 P1.5、P5.5、P5.6、iam `TOKENS.md` 一致，authz E2 为准）：Public 直接放行 → 验 token（格式、`alg` / `kid` / 签名、claim 类型、`iss`、`aud`、`typ`、`sub`、`exp` / `nbf` / `iat`、`jti`；不过答 401 `TOKEN_INVALID`）→ 还没拿到过 bundle：**每个非 Public 路由**（Authenticated 的也一样）答 503 `AUTHZ_NOT_READY` → bundle 里的 token 检查，按 E2 的顺序：`stale_since` 答 401 `TOKEN_STALE`；`dg` 在 `revoked_grants` 里答 401 `TOKEN_STALE`；委托 token 要 `delegation` 能力，`act` 链 `agent` 要 `agents`、`user`（代人登录）要 `impersonation`、`svc` 不再要别的，否则 401 `UNSUPPORTED_DELEGATION` → Authenticated 到此放行 → 路由键（已计入天花板 `ceil`）不在角色并集里答 403 `MISSING_PERMISSION`（`metadata.permission`）→ 放行，并把 `Access` 放进上下文。所以 stale 排在委托之前（iam AT-050 期望 `TOKEN_STALE`；AT-040 的上下文带 `impersonation: true`；iam 新增 impersonation=false、撤销的授予、`svc` 链但没有 delegation 三条用例）。每个业务路由必须声明一个守卫（权限键、Public 或 Authenticated），在 OpenAPI 上就是 `x-be-permission`（P3.16），没有"忘了写"这种状态（CP-AUTH-09…12） | MUST |
| P6.3 | 档位：`own < dept < subtree < all`（I2 改判，`dept` 现在就加）。对路由键 K，取所有授予 K 的角色里档位最高的那个；授予了 K 但没写档位，取角色的 `default_level`；还没有就是 `own`。资源维度的取值，按键取所有角色的并集；`*` 只能显式授予，表示全部；一个都没有就什么都看不到。`until` 按本地时间判定（CP-SCOPE-01…05） | MUST |
| P6.4 | 主体集合：`S(P) = {user:sub} ∪ {role:r} ∪ {dept:dept_path} ∪ {dept_tree:p \| p 是 dept_path 的祖先或自身} ∪ ⋃S(委托人)`。**R60**：`dept_path` 为空或格式不对时，两个 dept 项都不出现，部门数组为空，什么都匹配不到。只有 `"/"` 表示整棵树。"空串当根"永远不成立（CP-SCOPE-06） | MUST |
| P6.5 | 列表 SQL 用**规范谓词**，参数名固定：`@s_all`、`@s_owners[]`、`@s_dept_exact[]`、`@s_dept_prefix[]`（已经拼好 `%`、已转义）、`@s_<dim>_all`、`@s_<dim>_ids[]`、`@s_acl`、`@s_relations[]`、`@s_subjects[]`、`@s_graph_ids[]`。SQL 形状照抄 authz-architecture §3.5，仍然是静态参数化 SQL，没有 RLS（0206） | MUST（形状 INTERNAL；结果由 CP-SCOPE 测） |
| P6.6 | 单条记录判定：`Can(key, row)` 给出 `{visible, allowed, reason}`。看不看得见由资源类型声明里的 `view_key` 决定，动作由路由键 K 决定（K1 裁决 v）。**看不见**（对 `view_key` 而言，规则、共享、派生都不成立）时，读和命令一律 **404**（A3 细化 R62）。看得见但做不了，答 403：持有 K、但这条记录不在 K 的范围内是 `OUT_OF_SCOPE`，不持有 K 是 `MISSING_PERMISSION`。请求参数本身就是维度值、且不在范围内时（`warehouse_id=7`）也答 403 `OUT_OF_SCOPE`（CP-SCOPE-07…09） | MUST |
| P6.7 | **List 和 Can 一致**：一行出现在列表里，当且仅当对同一个路由键 `Can` 为 visible（CP-SCOPE-10，属性测试） | MUST |
| P6.8 | 字段级权限：`type: field` 的键。没有读键的字段在**源头**置为 null，并列进响应的 `_masked[]`；按掩码字段排序、过滤、聚合，答 400 `SORT_FORBIDDEN`；改了掩码字段，答 403 `FIELD_FORBIDDEN`（CP-SCOPE-11） | MUST（声明了字段键的组件） |
| P6.9 | 行按钮：列表响应里每一行带 `_access: {<action>: bool}`，前端不自己拼规则 | SHOULD |
| P6.10 | 资源契约。声明了 `resources` 的组件，SDK 自动挂出三组端点：`POST /{d}/{n}/_authz/check`（一次最多 500 条，返回 `[{visible, allowed, reason}]`）；`GET /{d}/{n}/_authz/explain?key=&type=&id=`（受 R62 约束：对看不见的记录只答本人一侧的事实）；`GET\|POST\|DELETE /{d}/{n}/_shares/{type}/{id}[/{share_id}]`。provider 缺某项能力时，答 501 `CAPABILITY_UNAVAILABLE`，并在 `metadata.capability` 里写能力名（CP-SCOPE-12…14） | MUST |
| P6.11 | 一致性令牌：入站带了 `X-Authz-Revision: N`，而本地投影的水位低于 N，就同步拉一次 changes（预算 300 ms）。还追不上：单条读回落到 provider 的 Check；列表照常返回，加响应头 `X-Authz-Consistency: stale`。`_shares` 写入后，等自己的投影追上返回的 revision 再响应（CP-SCOPE-15） | MUST（`sharing` 能力为真时） |
| P6.12 | ACL 投影：放在本组件 schema 的 `besdk_authz_acl` / `besdk_authz_cursor` 里（附录 A，`ddl/07-authz-projection.sql`），**只**在 `assembly.yaml` 声明了 `resources` 的组件的 schema 里建（P11.3、CP-DB-04）。拉取：`GET {AUTHZ_URL}/authz/v2/changes?types=…&after=<rev>&limit=500`，每 5 s 一次，收到 poke 时立刻拉；遇到 `410` 就用 `ReadTuples` 快照重建。只拉本组件声明的类型，以及它 `inherits` 的外部类型。**投影里只有直接元组**，主体一侧的展开在查询时现算 | MUST |
| P6.13 | 组件主责的关系（如商机团队）：在业务事务里调 `tx.SyncRelation(type, id, relation, subjects, version)`，写进 outbox，subject 是 `infra.authz.relation.sync.v1`。不直接调 `WriteTuples` | MUST |
| P6.14 | 决策不跨请求缓存：远程 Check 的结果只在本次请求内记住；`_authz/check` 的调用方不缓存结果（0201、authz-architecture §4.3） | INTERNAL |

### P7 系统面：组件之间的 gRPC

| # | 规则 | 等级 |
|---|---|---|
| P7.1 | gRPC 是组件之间的**系统协议**（0208）：不经边缘，不进 `edge_routes`。用户在用户请求路径上要读别的组件的受限数据，一律走用户面 REST（P8） | MUST |
| P7.2 | 出站 metadata：`traceparent` 和 `baggage`（OTel 注入）、`x-request-id`、`be-caller`（**必填**，本成员的组件 ID）、`be-actor-sub`（ctx 里有用户时填，每次调用现取）、`be-actor-act`（有代理链时，JSON 形式）。入站缺 `be-caller`，答 `UNAUTHENTICATED` + `MISSING_CALLER`（CP-RPC-01、02） | MUST |
| P7.3 | 服务端身份：上下文里标成系统主体 `System{Caller, ActorSub}`。契约里保留的面向用户的 rpc 从 gRPC 进来（没有用户 token），由运行时答 `UNAUTHENTICATED`，reason `TOKEN_INVALID`（domain `be`），不是 Internal，也不 panic（CP-RPC-03） | MUST |
| P7.4 | 可观察的部分：每一次调用，包括因身份（`MISSING_CALLER`）或批量上限（`BATCH_TOO_LARGE`）被拒的，都有 trace、计入 RED 指标、错误详情经过规范化。服务端拦截器顺序（INTERNAL），从外到内：trace → RED 指标 → panic recovery → 错误详情规范化 → 身份 → 截止时间下限（入站没带 `grpc-timeout` 时补 10 s）→ BatchGet 上限。一元和流各一条链 | MUST（顺序 INTERNAL） |
| P7.5 | 服务端参数：`MaxRecvMsgSize` 显式设为 4 MiB；`MaxConnectionAge` 取 `GRPC_MAX_CONNECTION_AGE`（默认 5 min），`MaxConnectionAgeGrace` 30 s，**必须大于最长的入站截止时间**（今天 30 s 对 10 s / 15 s；不满足时在途调用在换连接时被切断，R1 #2、#3）；`EnforcementPolicy.MinTime` 20 s 对 Go、Python 是 MUST，对 TS 不适用（grpc-js 服务端没有 keepalive 强制策略，R1 #3，widget-ts 在 compconf 里声明跳过对应断言）（CP-RPC-04、05） | MUST |
| P7.6 | 客户端连接按（成员，依赖，端口）复用，懒建。稳态下对同一个依赖只有一条 TCP 连接。keepalive：每 30 s 一次，超时 10 s，空闲时不发 ping（CP-OUT-01） | MUST |
| P7.7 | 出站截止时间：取 `min(3 s, 剩余预算 − 50 ms)`；剩余预算 ≤ 50 ms 时**不发出调用**，直接答 `DEADLINE_EXCEEDED` + `DEADLINE_BUDGET_EXHAUSTED`（CP-OUT-02） | MUST |
| P7.8 | 重试：方法标了 `idempotency_level = NO_SIDE_EFFECTS` 或 `IDEMPOTENT` 的，在 `UNAVAILABLE` 时重试：服务配置写 `maxAttempts: 3`，即**总共 3 次尝试**（首发 + 最多再试 2 次），三门语言、foundations 16 一致（R1 #2、#3，裁决 m）；退避 50 ms 起、上限 500 ms、倍数 2。其它方法只做透明重试（请求从未发出时）。重试预算用 `retryThrottling{maxTokens: 10, tokenRatio: 0.1}`；预算的范围**按语言不同**（裁决 az）：Go、Python 按 ClientConn / channel，也就是按（成员，依赖，端口，P7.6），所以一个成员的重试花不到别的成员的预算，并且每次 resolver 更新（dns 重新解析，最快 30 s 一次，通常跟着 GOAWAY）时预算回满；TS（grpc-js）按（进程，规范化的目标字符串），跨 channel 共享，resolver 更新时不回满。今天的 TS 只有 BFF，而 BFF 不进外壳，所以进程即成员；TS 若将来进外壳，SDK 在拦截器里自己做按成员的预算。"重试流量 ≤ 10 %" 是稳态上限，不是硬上限。带 `idempotency_key` 字段的 rpc 必须标 `IDEMPOTENT`，由门禁检查（CP-OUT-03、04） | MUST |
| P7.9 | 出站舱壁：每个成员对每个依赖最多 64 个并发调用，超了立刻答 `RESOURCE_EXHAUSTED` + `OUTBOUND_LIMIT`（CP-OUT-05） | MUST |
| P7.10 | BatchGet 上限：proto 字段选项 `[(be.v1.max_items) = N]`，没写就是 500（SDK 在服务注册时按方法路径遍历入参消息的**每个 repeated 字段**建一张上限表，请求时只比长度；map 字段不算 repeated 字段）。三门语言怎么读选项（r1-03b）：TS 读 ts-proto 的 `protoMetadata.options.messages.<Msg>.fields.<字段>.max_items`（键是扩展的短名，不带包名；嵌套消息在 `.nested` 下），不读 `fileDescriptor` 的 field options；Python 读 `field.GetOptions().Extensions[limits_pb2.max_items]`，besdk 随包附带可导入的 `be.v1.limits_pb2`；Go 用 `proto.GetExtension(fd.Options(), bev1.E_MaxItems)`，尚未实测，Go SDK 实现时验证。超限答 `INVALID_ARGUMENT` + `ErrorInfo{reason: BATCH_TOO_LARGE, metadata: {field, max, got}}` + `BadRequest`。调用方用 `BatchGetAll` 自动分片（D8）（CP-RPC-06） | MUST |
| P7.11 | 不做流式；不压缩，超过 1 MiB 的响应可以按调用开 gzip；proto 包名 `<domain>.<name>.v<n>`，只增（0302） | MUST |

### P8 出站：用户面 HTTP 与第三方 HTTP

| # | 规则 | 等级 |
|---|---|---|
| P8.1 | `UserHTTP(dep)`：只能在有用户的上下文里用。它转发调用者原始的 `Authorization`，以及 `X-Request-Id`、`traceparent`、`X-Authz-Revision`。上下文里没有用户（事件 handler、gRPC 系统调用里）就返回 `UNAUTHENTICATED`，**绝不悄悄换成系统身份**（CP-OUT-06） | MUST |
| P8.2 | `UserHTTP` 的超时同 P7.7；只有 GET 在连接被重置时重试一次；对方回的 problem+json 被还原成同样的状态码和 reason | MUST |
| P8.3 | `ExternalHTTP(name)` 调第三方（钉钉、Casdoor 这类）：默认超时 10 s，可以按名字配置；有 trace 和指标；**不转发**任何内部头（`Authorization`、`be-*`、`X-Authz-*`） | MUST |
| P8.4 | 事务里不许发网络调用：上下文带着"在事务里"标记时，SDK 的 `Conn`、`UserHTTP`、`ExternalHTTP` 都返回 `ErrNetworkInTx`（日志里的 reason 是 `NETWORK_IN_TX`，对外按 P4.3 是 `INTERNAL` 的通用文案），测试构建里直接 panic。事务里想触发对外动作，只有 `tx.Publish` 和 `tx.Enqueue` 两条路 | INTERNAL |

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
| RPC 重试 | 只对幂等方法的 UNAVAILABLE；总共 3 次尝试；预算是稳态额外流量 ≤ 10 %（范围按语言，见 P7.8） | P7.8 |

规则原文写进文档："子调用的超时必须短于调用方愿意等你的时间"（brickKit `09-patterns/04-service-calling`）。

### P10 数据库：身份、事务、池

| # | 规则 | 等级 |
|---|---|---|
| P10.1 | 库身份只来自配置，是两个分开的角色加一个 schema（F27，裁决 p）：**属主** `PG_OWNER_USER` 拥有本组件的表、只在迁移里做 DDL；**运行角色** `PG_USER` 只有 DML，不是属主角色的成员，是每个运行期事务都要切换到的角色；`PG_SCHEMA` 是 schema，最长 **40** 个字符（运行时由它派生的名字，如 `besdk_migrations_<PG_SCHEMA>`，要留在 PostgreSQL 63 字节的标识符上限之内；约定 `07-registries.md` 由控制者补同一条）。三者都必填，没有默认值，也不互相推导、不从组件 ID 推导。防住的威胁：运行期的 SQL（注入、AI 写出的语句）不能 DROP / ALTER。代码、迁移、测试夹具里都不出现 `_rw`、`_archive`、`shell_` 这类派生名，也不出现本组件的 schema 或角色字面量（R63）（CP-DB-01：套件用随机 schema、随机角色、NOINHERIT 的外壳角色跑完全部 profile） | MUST |
| P10.2 | 每一次数据库访问都在事务里，并且开头先执行 `SET LOCAL ROLE <PG_USER>`、`SET LOCAL search_path TO <PG_SCHEMA>` 和 `SET LOCAL application_name = '<组件 ID>'`（外壳里是成员 ID；R1 #5：`pg_stat_activity.usename` 在外壳里永远是外壳的登录角色，只有 `application_name` 能区分成员）。此外每条池化连接在建连时带会话级的 `application_name` = `<组件 ID>@<版本>`，事务里的 `SET LOCAL` 只在事务期间覆盖它；服务期间每个成员至少保持一条会话在线，契约迁移靠它判断旧版本是否还在跑（P11.4）。这包括业务事务、outbox 泵、消费、Jobs、生命周期、投影拉取和启动探测，没有例外。search_path 里只有本组件的 schema（不再有 `_archive`，D2）。池化连接上的会话级 `SET` 一律禁止；唯一的例外是专用、不进池的迁移连接（P11.1）。**语句缓存的键必须包含成员的 schema**（R1 #4、r1-04b，裁决 ay；INTERNAL）：Go 保持 pgx 默认的 `QueryExecModeCacheStatement`、Python 保留 asyncpg 的缓存，`Tx` 在每条 SQL 前面加 `/* be:<PG_SCHEMA> */ `；两者都按 SQL 文本建键，于是两个成员永远不共用一条预编译语句（否则形状不同的表会确定性地报 `0A000` / `42804`）。pgx 的 `QueryExecModeCacheDescribe` **修不好**（列数不同报 `08P01`，参数类型不同仍是 `42804`），foundations-data-platform DB-6 的这条建议撤回。外壳里 pgx 的 `StatementCacheCapacity`、asyncpg 的 `statement_cache_size` 按成员数放大。TS 的 pg 保持默认的未命名语句，要用命名语句时 `name` 必须带成员前缀。`0A000`、`08P01` 不加进 P10.4 的自动重试 | MUST（INTERNAL） |
| P10.3 | 每个事务都用 `SET LOCAL` 设三个超时：`statement_timeout = min(5 s, 剩余预算)`、`lock_timeout = 2 s`、`idle_in_transaction_session_timeout = 30 s`。服务端 ≥ 17 时再按剩余预算设 `transaction_timeout`。会话时区永远是 UTC（CP-DB-02：套件先持锁，被测组件在 `lock_timeout` 内答 409 + `LOCK_TIMEOUT`） | MUST |
| P10.4 | 隔离级别默认 READ COMMITTED，单个事务可以选 RR 或 SERIALIZABLE。40001 / 40P01 由 SDK 回滚，重新执行整个事务函数，最多 3 次。用尽后答 `ABORTED` + `TX_CONFLICT`。55P03 映射成 `ABORTED` + `LOCK_TIMEOUT`，57014 映射成 `DEADLINE_EXCEEDED` + `STATEMENT_TIMEOUT`（调用方取消引起的 57014 是 `CANCELLED` + `REQUEST_CANCELLED`），53300 映射成 `UNAVAILABLE` + `DB_TOO_MANY_CONNECTIONS`；连不上库、连接断开、SQLSTATE 类 `08`、`57P01`、`57P02`、`57P03` 映射成 `UNAVAILABLE` + `DEPENDENCY_UNAVAILABLE`（`metadata.dependency = db`）。重试计入 `be_tx_retries_total{sqlstate}`（`40001` / `40P01`） | MUST |
| P10.5 | 池：单跑时的上限是 `PG_POOL_MAX`。外壳里物理池的大小取 `min(Σ 成员的 PG_POOL_MAX, 外壳自己的 PG_POOL_MAX)`，每个成员再挂一个容量为它自己 `PG_POOL_MAX` 的信号量。取不到连接时最多等 `PG_POOL_ACQUIRE_TIMEOUT`，超时答 `RESOURCE_EXHAUSTED` + `DB_POOL_EXHAUSTED`。一个成员耗尽，不影响别的成员（CP-DB-03：套件压满并发，`pg_stat_activity` 里 `application_name` 等于该组件 ID、且不是 idle 的连接数 ≤ `PG_POOL_MAX`；按 `usename` 计数在外壳里永远是 0，R1 #5）。保持多少空闲连接是各 SDK 连接池自己的行为（`PG_POOL_MIN_IDLE` 已退役，见 P2 表下的说明），但服务期间每个成员至少有一条会话在线（P10.2、P11.4） | MUST |
| P10.6 | 一个执行流同一时刻最多占一条连接：已经在事务里，再开事务就返回 `ErrNestedTx`；消费 handler 的 `Apply` 拿到的就是 SDK 的那个事务。这是池饥饿的根治办法 | INTERNAL |
| P10.7 | 启动探测在后台跑，不放进 `/healthz`。**能力**：只读 `current_setting('server_version_num')::int`，要求 ≥ 140000，外壳里 ≥ 160000（外壳要 PG16 的 `GRANT … WITH INHERIT FALSE, SET TRUE`，R1 #5，裁决 n）；声明式分区（PG 10）和 `SKIP LOCKED`（9.5）由 ≥ 14 隐含，不另外探；缺了是致命错误。**身份**（`SET LOCAL ROLE` 之后，在同一个事务里跑 be-protocol 列出的那几条目录查询）：对 schema 有 `USAGE`、没有 `CREATE`；`pg_has_role(current_user, <PG_OWNER_USER>, 'MEMBER')` 为假；schema 里每张表的属主都是 `PG_OWNER_USER`，`PG_USER` 对每张表都有 DML。身份失败时记 ERROR，`be_db_identity_ok = 0`，`/readyz` 答 503，不退出。（R1 #4 顺带发现：没有 USAGE 时 search_path 那一项被静默跳过、报的是 `relation does not exist`，这条探测必须保留） | MUST |
| P10.8 | advisory 锁只用事务级的，键是 `pg_advisory_xact_lock(hashtext(current_schema() \|\| ':' \|\| name), hashtext(key))`。所以外壳里成员之间不会撞键，"单跑和外壳同时在跑"时，同一个 schema 自然互斥。会话级锁一律禁止（与 pgbouncer 的 transaction 模式兼容） | MUST（INTERNAL） |
| P10.9 | 队列认领、幂等认领都是原子的：`FOR UPDATE SKIP LOCKED`，或者 `INSERT … ON CONFLICT DO NOTHING / DO UPDATE … WHERE … RETURNING`。先 `SELECT` 再写，一律禁止（现有易错点） | MUST |
| P10.10 | 一个事务要锁多行时，按主键或业务唯一键的固定顺序加锁（库存多品预留，foundations-communication §3.4 第 5 条） | MUST（组件义务） |
| P10.11 | pooler 可选；用就只用 transaction 模式。PgBouncer ≥ 1.21 且 `max_prepared_statements > 0` 时驱动的语句缓存可以开着，其它 pooler 一律关掉。迁移经 `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` 直连 | MUST |
| P10.12 | 运行中的服务**从不**以 `PG_OWNER_USER` 登录（已知限制见 P2 表）。服务运行期间生命周期引擎要做的 DDL（提前建分区、装封存守卫、删过期的平台或队列分区）只经平台的 `SECURITY DEFINER` 函数执行（be-protocol `ddl/10-lifecycle-functions.sql`：`besdk_ensure_range_partition`、`besdk_ensure_list_partition`、`besdk_seal_table`、`besdk_drop_partition`），这些函数由属主在平台迁移里建（裁决 aa）（CP-DB-05） | MUST（部分 INTERNAL） |

### P11 迁移与数据形状

| # | 规则 | 等级 |
|---|---|---|
| P11.1 | 迁移以**属主** `PG_OWNER_USER`（口令从 `PG_OWNER_PASSWORD_FILE` 指向的文件读）登录，直连库（有 `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` 就用它们，否则退回 `PG_HOST` / `PG_PORT`）（F27，裁决 p）。会话参数 `lock_timeout = 5 s`、`statement_timeout = 15 min`。拿锁超时就退避重试 3 次，最后仍失败时记下阻塞者的 pid 和等待事件；它们的 SQL 文本（截前 200 字）只在看得见时才记（`pg_stat_activity` 对别的角色隐藏查询文本，属主角色**不**被授予 `pg_read_all_stats`，权限太宽）。迁移连接是专用会话：迁移工具自己的会话级 `search_path` 和会话级 advisory 锁在这里允许，P10.2、P10.8 的禁令只针对运行期的池化连接（R1 #6）。迁移锁按 schema 区分：两个组件同时迁移同一个库都成功（node-pg-migrate 的默认锁是全库常量，TS SDK 必须改，见 apis §4） | MUST |
| P11.2 | 迁移文件里不出现 `OWNER TO`、`GRANT`、`REVOKE`、`CREATE SCHEMA`、`CREATE ROLE` / `ALTER ROLE`、`SET`，不出现限定名，不出现角色或 schema 字面量，也不出现日期字面量的分区。名字都不带限定，靠 search_path 解析（R63、data-layer §2.6） | MUST |
| P11.3 | 迁移的状态表放在本组件的 schema 里，表名写死（R1 #6）：Go `schema_migrations_<PG_SCHEMA>` + `besdk_migrations_<PG_SCHEMA>`；Python `_yoyo_migration`、`_yoyo_log`、`_yoyo_version`、`yoyo_lock`（平台迁移 id 带 `besdk-` 前缀，共用这几张）；TS `pgmigrations_<PG_SCHEMA>` + `besdk_migrations_<PG_SCHEMA>`。这些表列入 P11.11 的白名单。组件迁移跑完之后，在同一个迁移步骤里、仍以属主身份，SDK 再跑一段**平台迁移**，内容依次是：建或升级 `besdk_*` 表和平台函数（P10.12；版本记在 `besdk_platform_version`；授权投影的两张表 `ddl/07-authz-projection.sql` 只在 `assembly.yaml` 声明了 `resources` 的组件里建，CP-DB-04 恰好在那时期望它们）；按 `lifecycle.yaml` 建出当前分区窗口（分区名见 P16.6）；确保事件流和本组件的 durable 存在（P12.4）。三者都幂等 | MUST |
| P11.4 | 演进遵守 expand / contract：contract 类迁移的文件头写 `-- be:contract after=<version>`；`CREATE INDEX CONCURRENTLY` 单独一个文件，文件头写 `-- be:no-transaction`。生产只前滚（foundations-data-platform §6.4）。**契约迁移门禁**（brickKit 不做 FR06-020，所以由运行时自己做）：每条池化连接带会话级 `application_name` = `<组件 ID>@<版本>`（P10.2），服务期间每个成员至少一条会话在线（单跑时池不降到 0 条；外壳里每个成员一条空闲的"在场"会话，名为 `<成员 ID>@<成员版本>`）。迁移器跑到首行是 `-- be:contract after=<version>` 的文件之前，查 `pg_stat_activity`（`application_name` 对每个角色都可见）：只要还有别的会话名为 `<同一个组件 ID>@<v>` 且 v ≤ `<version>`（按 semver 比），就停在这个文件之前：前面的文件保持已应用，记一条 ERROR（点名文件、挡路的版本和会话数），以 1 退出。所以 `after=<version>` 的含义是"最后一个还在用这一步要删的东西的版本"，这一步要等那个版本及更早的会话都不在线了才跑（foundations 08） | MUST |
| P11.5 | 自有主键一律 UUIDv7，列类型 `uuid`，由应用生成。分区表的 `created_at` 必须等于 `IDTime(id)`。外部引用保持 `TEXT`（F3）。线上仍是不透明字符串 | MUST |
| P11.6 | 金额 `NUMERIC(19,4)`；单价、成本、数量 `NUMERIC(19,6)`；汇率 `NUMERIC(19,10)`。金额与币种 `CHAR(3)` 总是成对出现。舍入只在 SDK 的 money 包里做，按 ISO 4217 的小数位，默认 HALF_AWAY_FROM_ZERO。线上仍是十进制字符串（0301）（F4） | MUST |
| P11.7 | 瞬时用 `timestamptz`；业务日期用 `DATE`，按**法人**的业务时区算。SQL 里禁止 `CURRENT_DATE`、`now()::date` 和 `date_trunc(…, now())`，"今天"由 SDK 算出来作为参数传入。事件带单据的业务日期（F5） | MUST |
| P11.8 | 交易单据表带 `legal_entity_id TEXT NOT NULL`；事件 payload 也带它。缺法人的事件，消费方拒收（进 DLQ），不悄悄记进 `default`（F2、Q2） | MUST |
| P11.9 | 法人日历：时区、会计年度起始月、本位币，来自 `mdm/org`，由 SDK 的快照帮手维护；汇率来自 `mdm/currency`。两者本轮新建，排在其余组件升 3.0.0 之前（用户答复 P2），所以没有过渡用的 `LEGAL_ENTITIES` 共享变量，汇率也不限定为 1。mdm/org 与 IAM 目录（部门）怎么分工，在 mdm/org 自己的设计里定。没装 mdm/org 时（夹具、单独调试）日历进**降级模式**：时区取 `BUSINESS_TIMEZONE`，会计年度起始月为 1，并在 `/_be/info` 里标出（S-b 裁决 as）。SDK 必须内嵌时区数据：Go `time/tzdata`、Python `tzdata` 包、Node 完整 ICU；tzdata 变了就重跑向量交叉核对（裁决 ar） | MUST |
| P11.10 | 单据编号：`besdk_number_series` 表，`tx.NextNumber(series)`。凭证这类 `gapless=true` 的，在同一事务里锁行，按期连续、无缺号（F8，每个法人串行，吞吐上限写进文档）；其余按块预取，允许缺号。格式由组件配置给出（`<NAME>_NO_FORMAT`）。**唯一性**由一张不分区的分配表保证：`besdk_number_allocations`，主键 `(legal_entity_id, series, number)`，和单据在同一个事务里插入；不靠分区单据表上的唯一索引（分区表的唯一索引必须包含分区键，管不住跨分区重号，S-b 裁决 ao） | MUST |
| P11.11 | 业务表、迁移里的表，都在 `lifecycle.yaml` 里有声明（P16）；`besdk_*` 表和 P11.3 的迁移状态表除外；迁移目录里只放 `*.sql` 和 `lifecycle.yaml` | MUST |

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
| `tracestate` | W3C；只在非空时带（outbox 的 `tracestate` 列） | SDK |

| # | 规则 | 等级 |
|---|---|---|
| P12.1 | 发布只经 outbox：和业务写入在**同一个事务**里写 `besdk_outbox`。泵在事务外发布，拿到持久化确认（JetStream 的 PubAck）后才标成 `PUBLISHED`；总线不可用时行留在 `PENDING`，按 `next_attempt_at` 退避（1 s → 1 min），**永不丢弃**，积压由告警发现。认领用 `SKIP LOCKED`。轮询间隔自适应：忙时 200 ms，空闲时退到 2 s。最多 256 个确认同时在途（CP-EVP-01…04：停掉总线 → 执行命令仍然成功 → 恢复总线 → 事件送达，不丢、不重） | MUST |
| P12.2 | payload 是 JSON，用 `contracts/events/*.json`（JSON Schema）校验，契约里写明 `x-aggregate-type` 和 `x-consumption: state\|sequence`；序列化后的 JSON 超过 64 KiB（65,536 字节）的 payload 在发布时**必须**被拒绝（outbox 写入失败；这是编程错误，`INTERNAL`），rc.1 的"硬上限 1 MiB"取消；超过的内容走对象存储 claim-check：对象放在**生产者自己的** bucket，payload 只带 `{key, sha256, size}`，生产者另提供一个 rpc 换取短期有效的 URL（D3b 裁决 d）。payload 里不放给人看的敏感字段（CP-EVP-05） | MUST |
| P12.3 | subject 命名：至少 4 段，`<domain>.<name>.<event…>.v<N>`；每一段匹配 `[a-z][a-z0-9]*(_[a-z0-9]+)*`（没有开头、结尾或连续的下划线），第一段选流，最后一段是 `v<N>`（S-b 裁决 am）。历史上的 `sales.*`、`finance.*` 保留（E10）。一个 subject 只由一个组件、或一个槽位族的每个成员发布；唯一的例外是 `infra.authz.relation.sync.v1`，每个主责关系的组件都发（P6.13，K1 裁决 y）。同一个生产者、同一个聚合类型的所有 subject 共用一个单调递增的版本 | MUST |
| P12.4 | 流：按 subject 第一段，名叫 `BE_<第一段大写>`，subjects 是 `<第一段>.>`；默认 7 天、1 GiB、丢旧、去重窗口 10 min、文件存储、单副本；DLQ 流 `BE_DLQ` 保留 30 天。规则是"没有就建，有就不碰"，在平台迁移和启动时各执行一次（E1、E2） | MUST |
| P12.5 | durable：每个（组件，subject）一个 pull 消费者，名字是 `<组件ID的/换成_>__<subject的每个.换成__>`（`erp_finance__sales__order__created__v1`）；推导是单射的：组件 ID 里没有 `_`，按 P12.3 的段格式段里没有 `__`、也不以 `_` 开头或结尾，所以名字在每个 `__` 处都能唯一拆回（`crm.lead.stage_changed.v1` 和 `crm.lead_stage.changed.v1` 得到不同的名字；X2-F1 发现的旧写法 `.`→`_` 撞名问题，按裁决 aw 的更正改用 `__` 解决）。服务端参数全部是**协议常量**：AckWait 30 s（就是 handler 的真实期限），MaxAckPending 256，**不设 BackOff**，**MaxDeliver −1**，首次建时 `DeliverAll`（E3），InactiveThreshold 30 天；重投延迟和投递上限由 SDK 执行（P12.7，R1 #7，裁决 ax）。原因：设了 BackOff，服务端就把 AckWait 改成 BackOff[0]，`Nak()` 又不看 BackOff 立刻重投，InProgress 也挡不住 1 s 的期限，同一条事件会被并发执行两次。durable **只在不存在时创建，从不更新**：Go / JS 用"仅创建"的 API；Python 先 `consumer_info`，不存在才 `add_consumer`（nats-py 的 `add_consumer` 是"创建或更新"，不能直接调）；读回的配置与常量不一致时记 WARN、不覆盖。单跑、进外壳、多副本，用的都是同一个 durable（CP-EVS-01） | MUST |
| P12.6 | 去重靠**聚合流游标**：`besdk_event_cursor` 的主键是 `(consumer, aggregate_type, aggregate_id)`，推进游标和业务写入在同一个事务里（附录 A 的 upsert）。语义是"状态模式"：比游标旧的版本直接跳过，handler 要写成"把聚合推进到第 v 版"。乱序和重复投递之后，最终状态与按序投递一次相同（CP-EVS-02、03，属性测试）。订阅**可以**声明自己的聚合类型（三门 SDK 都有这个可选字段）；不声明时，运行时取消息的 `ce-aggregatetype` 头作为游标键 | MUST |
| P12.7 | 两种 handler：`Apply` 在游标所在的事务里，只做本地写；`Run` 在事务外执行，可以走网络，成功后用一个短事务推进游标，必须按业务键幂等。handler 第 n 次投递出错，SDK 发 `NakWithDelay(EVENTS_BACKOFF[min(n−1, len−1)])`（三个客户端都有：Go `NakWithDelay`、Python `nak(delay=)`、JS `nak(millis)`）；超时或进程崩溃造成的重投固定隔 AckWait。**最后一次允许的投递**（投递次数 d = `EVENTS_MAX_DELIVER`）失败时和别的失败一样 Nak；消息在**下一次收到时**（d > max）、handler 运行之前写 DLQ 后 `Term`。`Permanent` 错误立刻写 DLQ + `Term`，不 Nak。所以"最后一次投递时进程崩溃"也能进 DLQ（AckWait 之后重投，d > max），不依赖 `MAX_DELIVERIES` advisory（r1-07 的说明同此）。`EVENTS_MAX_DELIVER` / `EVENTS_BACKOFF` 的取值优先级见 P2 表：键（设了时）> 订阅 > 内置。DLQ 消息的 `Nats-Msg-Id` 是 `dlq:<durable>:<stream_seq>`（多副本、外壳里重复写会被去重），subject 是 `dlq.<durable>.<原 subject>`，带原来的 `ce-*` 头和 `be-dlq-reason`、`be-dlq-consumer`、`be-dlq-delivery`（CP-EVS-04、05） | MUST |
| P12.8 | `ce-hopcount > 10` 直接进 DLQ（防环）。在 handler 或 Job 里发布的事件，`causationid` 和 `hopcount` 自动派生（CP-EVS-06） | MUST |
| P12.9 | 处理慢时每过 AckWait/3 发一次 `InProgress`（只有在 P12.5 不设 BackOff 时才成立，R1 #7）。每个订阅默认 4 个并发，同时受本成员 DB 预算的约束。正确性永远不依赖 broker 的顺序 | MUST |
| P12.10 | 即时信号（poke），比如 `infra.authz.changed.v1`：尽力而为，可以丢，不持久、不重投。事件契约里用 `x-signal: true` 标出：不走 outbox，不列进 `component.yaml` 的 `events.publishes`，没有 durable。外壳里每个成员各订阅一次 | MUST |
| P12.11 | 回放分三档：①流的保留期（7 天）以内，建一个从指定时间开始的临时消费者；②超过流的保留期、仍在 outbox 的保留期（发布后 14 天，data-lifecycle-v2 §4.7）以内，从生产者的 outbox 重发，`Nats-Msg-Id` 加后缀避开去重窗口，消费者靠游标去重（`make events-replay`）；③更早的历史不再重放事件，新消费者走上游的 `List` 回填（P15.3），遇到 `RANGE_COLD` 就改读上游发布的数据集 | MUST（生产者保留 outbox 14 天） |
| P12.16 | `component.yaml` 向 brickKit（≥ v1.3.0）声明事件，只用于 `graph`、`deps`、`lint`：`events.publishes` 恰好是事件契约里的 subject（槽位族成员取族的 subject），`events.subscribes` 是经 durable 消费的每个 subject，与 `conformance/fixtures.yaml` 的 `events.consumes` 相同。整段由 be-ops 从这两个文件生成（O1）。P12.3 的 subject 直接就是合法的 brickKit 事件名；`subscribes` 里只有真按前缀订阅的消费者才写结尾 `*`；尽力而为的 poke（契约里 `x-signal: true`，P12.10）不列。运行期没有任何作用；门禁 `events-declaration-scan` 对照契约和夹具，套件对照实际发布和建出的 durable（CP-EVP-06、CP-EVS-09） | MUST |
| P12.12 | 总线适配器由 `EVENT_BUS_URL` 的 scheme 选：`jetstream`（默认）、`pgqueue`（schema `be_bus`，由 db-init 建）、`kafka`（预留）。运行时没有适配器的 scheme 让启动失败并点名它（非 0 退出，不是 78）；官方 SDK 先只带 `nats://`，PostgreSQL 队列适配器随后补上。pgqueue 用组件自己的 `PG_USER` / `PG_PASSWORD_FILE` 连库（所以走队列总线的组件要声明 db 的键）；`be_bus` 的分区只经 NOLOGIN 角色 `be_bus_owner` 拥有的 `SECURITY DEFINER` 函数维护（和生命周期函数同一个套路，P10.12）；项目的初始化脚本给 `be_bus.message` 建一个 DEFAULT 分区，所以发布永远不会因为缺分区而失败。适配器必须通过 `tools/be-acceptance/conformance/bus/`（busconf，§4.8）。pgqueue 按与 P12.5、P12.7 相同的语义实现：失败 → `next_attempt_at = now + EVENTS_BACKOFF[n−1]`；投递次数 > `EVENTS_MAX_DELIVER` → DLQ；busconf 有一条"Nak 之后重投不早于 `EVENTS_BACKOFF[n−1]`" | MUST |

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
| `Cron` | 每个时间槽全局只跑一次。用 `INSERT … ON CONFLICT DO NOTHING` 抢槽，不需要领导者。错过的槽只补跑最近一个。调度写成 5 字段的 cron 表达式，**或** `@every <时长>`（S-b 裁决 an）。时区默认 `BUSINESS_TIMEZONE` | `besdk_job_slot` |
| `Queue` | 在业务事务里入队，至少执行一次。认领用 `SKIP LOCKED`；按退避重试；重试用尽进 `dead` 状态，并调用 `OnDead`；可选的 `unique_key` 保证同一个键只入队一次 | `besdk_job_queue` |
| `Reconciler` | 按"非终态且已过期"扫描候选；逐行原子认领、带租约；`Handle` 在事务外执行，`Apply` 在短事务里推进；退避；超过上限调用 `GiveUp`（挂起 + 开异常待办） | `besdk_reconcile` |

| # | 规则 | 等级 |
|---|---|---|
| P14.1 | 组件里所有不由请求触发的工作，都必须登记成上面五种之一。模块代码里不许自己写 ticker 循环（门禁 `module-ticker-scan`） | MUST（INTERNAL） |
| P14.2 | 监督见 P1.7。每次运行有超时，超时就取消（CP-JOBS-01…05：两个副本同一个 Cron 槽只跑一次；Singleton 同一时刻只有一个；Queue 每个作业只执行一次；业务事务回滚则作业不存在；任务失败后被重启） | MUST |
| P14.3 | 指标：`be_job_runs_total{job,result}`、`be_job_duration_seconds`、`be_job_last_success_timestamp_seconds`、`be_queue_depth{kind,state}`、`be_queue_oldest_age_seconds`、`be_reconcile_pending{name}`、`be_reconcile_oldest_age_seconds`、`be_reconcile_giveups_total` | MUST |
| P14.4 | 只读的运维端点 `GET /{d}/{n}/_ops/jobs`，权限键 `<domain>.<name>.ops`，由 be-ops 自动登记 | SHOULD |
| P14.7 | 平台表的保留默认值：`besdk_job_queue` 里状态 `done` 的行 7 天，`besdk_job_slot` 的行 30 天；与之并列的是 outbox 发布后 14 天（P12.11）、游标和幂等行 30 天（P13.7、附录 A）。由 SDK 的平台清理任务执行，在 P16 的表类别里登记（foundations 19、09） | MUST |
| P14.8 | 跑一次就退出（可选能力，`/_be/info` 的 `capabilities` 列出 `job_run`）：`<entrypoint> job run <name>` 用同一个镜像、配置和密钥文件，核对 schema 版本，不起服务、不起别的后台工作，经同一批表把任务跑**一次**后退出（0 成功或无事可做，1 失败，64 任务名不存在（和不认识的参数一样，P1.1），78 配置错误）。重任务经测量要移出进程时：`JOBS_OVERRIDES` 设 `enabled: false` 关掉进程内那一份，在平台之外触发（宿主机 cron / systemd 定时器执行 `docker compose --project-directory <根> -p <项目> -f .brickkit/generated/compose.yaml run --rm --no-deps <服务> job run <name>`；或不带 `brickkit.io/project` 标签的手写 K8s CronJob）。FR06-007 不做，0508 不变（bk9）（CP-JOBS-06） | MAY |

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
| P16.2 | 引擎作为 Singleton 运行；每一步一个事务，加一把步骤锁（P10.8），设 `lock_timeout`。运行角色没有 DDL 权（P10.12）：运行期里只经平台的 `SECURITY DEFINER` 函数提前建分区、装封存守卫、删到期的 platform / queue 分区（短 `lock_timeout` 下的普通 `DETACH`）；`DETACH … CONCURRENTLY` 不能在函数或事务块里跑，所以已冷冻业务单元的 detach 和 drop 放在迁移步骤里，以属主身份在它的专用连接上做。必须守住 data-lifecycle-v2 §4.5 的 G1–G12 | MUST（INTERNAL，由 `lifecycleconf` 测） |
| P16.3 | 读一个时间范围：要么拿到完整结果，要么答 `RANGE_COLD`，并在 `metadata` 里给出冷区间、能否解冻、能否异步导出。不静默截断。List 请求有可选字段 `include_cold`（CP-LIFE-02） | MUST |
| P16.4 | 资源契约 `/{d}/{n}/_lifecycle/*`（OpenAPI 片段和 gRPC `be.lifecycle.v1` 都在 be-protocol 里），端点全部挂出；还没实现的答 501 `CAPABILITY_UNAVAILABLE`（CP-LIFE-03） | MUST |
| P16.5 | 封存单元不可改：UPDATE / DELETE / TRUNCATE 被拒，映射成 `FAILED_PRECONDITION` + `UNIT_SEALED` | MUST |
| P16.6 | 迁移跑完的当天就能写入：分区窗口由平台迁移建好（CP-LIFE-01：在新库上迁移后立刻写一条 outbox）。运行时建的范围分区命名：粒度为周时 `<父表>_<ISO 周年>w<WW>`（outbox：`besdk_outbox_2026w40`），月 `<父表>_<YYYY>m<MM>`，年 `<父表>_<YYYY>`；边界是 UTC 的左闭右开 [start, end) | MUST |

### P17 对象存储

| # | 规则 | 等级 |
|---|---|---|
| P17.1 | 走 S3 API，地址 `S3_URL`；浏览器走 `S3_PUBLIC_URL`。每个组件一个 bucket、一套凭据，策略只允许访问自己的 bucket（foundations-data-platform §8.2）。冷数据也放在组件自己的 bucket 里，前缀 `cold/<table>/…`（D3b 裁决 c） | MUST |
| P17.2 | 大文件不进 gRPC 或 REST 的响应体，返回预签名 URL（有效期 ≤ 5 min，按 `S3_PUBLIC_URL` 签）或附件 ID。bucket 永不公开读 | MUST |

### P18 可观测性

**P18.1 trace**：W3C TraceContext + Baggage。HTTP 和 gRPC 的入站提取、出站注入；事件把 `traceparent` 写进信封，消费端开一个新的 span，用 **span link** 指向生产者，不作为它的子 span。resource 属性：`service.name` 是组件 ID，`service.version`，`service.namespace` 是组件的领域（组件 ID 的第一段，如 `erp`），`service.instance.id`，`deployment.environment.name` 取 `DEPLOY_ENV`（OpenTelemetry 语义约定 ≥ 1.27 的名字，原先叫 `deployment.environment`）。入站 `traceparent` 的 sampled 标志是 0 时照样传播（trace ID 保留，子 span 也不采样），它的 span 不记录、不导出；`trace_id` 仍出现在日志和 problem 体里。外壳里**每个成员一个 TracerProvider 和 MeterProvider**（CP-OBS-01…03：HTTP → gRPC → outbox 事件 → 消费，是同一个 trace_id 或者有一条 link）。R1 #1 补的三条（裁决 o）：①所有埋点（otelgrpc、otelgin / otelhttp、Python 的拦截器）一律**显式**传成员的 `TracerProvider`、`MeterProvider` 和平台的传播器，不靠全局，否则 span 进全局 provider、每一跳都断；②全局只装传播器（TraceContext + Baggage），全局 `TracerProvider` 设成外壳自己的（`service.name` = 外壳 ID），漏传选项的埋点一眼可见；③共享导出器的关闭归平台，见 P19.3。

**P18.2 日志**：stdout，一行一个 JSON 对象，最长 **2048 字节，含结尾的换行**。信封字段永不截断：`time`、`level`、`msg`、`component_id`、`component_version`、`trace_id`、`span_id`、`request_id`、`truncated`；其余字符串值都可以截，最长的先截，在字符边界上截，末尾标 `…[TRUNCATED]`，并置 `truncated: true`。

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
| `truncated` | 截断过时 | 信封字段，永不截 |

**P18.4**：受保护路由的访问日志行带 `sub` 和 `perm`；鉴权之前答出的 413 例外（P3.6）。原始 token 从不进任何日志行。

PII 与密钥键自动脱敏（S-b 裁决 aq，以向量 `redaction` 的语义为规范）：受保护的名字是 `phone`、`mobile`、`id_card`、`password`、`bank_card`、`email`、`token`、`secret`、`authorization`、`cookie`、`set-cookie`、`api_key`；字段名按 snake_case / camelCase 切成词，**整词**匹配（`contact_phone`、`apiKey` 命中，`tokenizer` 不命中），值整体换成 `"[REDACTED]"`；截断到 2048 字节之后这一行仍是合法 JSON。三门语言都在 handler 里自动做，不靠业务代码去调。

**P18.3 指标**：Prometheus 文本格式，在主端口的 `/metrics` 上。每个序列都带 `component` 标签；外壳里汇总所有成员的指标，同样带这个标签（V-08）。

| 名字 | 类型 | 标签 |
|---|---|---|
| `be_http_server_requests_total` | counter | `method` `route`（模板，不是原始路径）`status_code`（数字） |
| `be_http_server_duration_seconds` | histogram | `method` `route` |
| `be_grpc_server_handled_total` / `_duration_seconds` | counter / histogram | `service` `method` `code` |
| `be_grpc_client_handled_total` / `_duration_seconds` | counter / histogram | `target` `method` `code` |
| `be_outbound_inflight` | gauge | `target` |
| `be_db_pool_in_use` / `be_db_pool_wait_seconds` | gauge / histogram | — |
| `be_tx_retries_total` | counter | `sqlstate`（`40001` / `40P01`；rc.1 是 `reason`） |
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
| P19.3 | 整个进程只有四样东西是共享的：OTel 导出器和传播器（**共享导出器只由平台在所有成员停完之后关闭**；每个成员的 provider 有自己的 BatchSpanProcessor，包着一层 `Shutdown` 为空操作的导出器壳，成员停止时只刷出自己的队列。R1 #1：朴素地共享导出器或 BSP，第一个成员一停导出器就关了，之后别的成员的 span 静默丢失，`Shutdown` 还返回 nil）；JWKS 验签器和 bundle；DB 物理池；总线连接。共享的前提是各成员的 `AUTHZ_URL`、`IAM_*`、`TENANT_ID`、`PG_HOST` / `PG_PORT` / `PG_DATABASE`、`EVENT_BUS_URL` 都和外壳自己的一致（哪些键是整个进程一个值，由 `config-keys.yaml` 的 `shell: process` 标出）；任何一项不一致都拒绝启动（修"静默忽略成员的 PG_HOST"）（CP-SHELL-03） | MUST |
| P19.4 | 其余的一切按成员实例化：Logger、Prometheus Registry、TracerProvider 和 MeterProvider（`service.name` 是成员 ID）、`Store`（成员的身份 + 成员的连接预算）、gRPC 连接池和出站舱壁、durable、Jobs、缓存、ACL 投影、生命周期引擎（CP-SHELL-04、05） | MUST |
| P19.5 | 外壳的登录角色是 NOINHERIT 的，只通过 `SET LOCAL ROLE` 进入成员的**运行角色** `PG_USER`（`GRANT <成员运行角色> TO <外壳角色> WITH INHERIT FALSE, SET TRUE`），所以**外壳要求 PostgreSQL ≥ 16**，单跑的组件仍以 14 为下限（R1 #5，裁决 n）。外壳从不被授予任何成员的属主角色；成员的迁移仍由各自的迁移容器以各自的 `PG_OWNER_USER` 跑（裁决 p）。成员之间的隔离靠 SDK、不靠数据库：外壳角色对每个成员都有 SET 权，成员代码若自己执行 `SET ROLE` 就能切到别的成员（R1 #5 C11），所以 SDK 的 `Store` 是唯一发 `SET LOCAL ROLE` 的地方，门禁 `identity-literal-scan` 禁止组件代码里出现 `SET ROLE` / `SET LOCAL ROLE` 和角色字面量（CP-SHELL-07） | MUST |
| P19.6 | 外壳的 `/healthz` 只答外壳进程本身。成员初始化失败，整个外壳就启动失败；成员运行中的后台任务失败，由监督重启，不永久停止（CP-SHELL-06） | MUST |
| P19.7 | 外壳在自己的端口上暴露汇总的 `/metrics`；每个成员的 `/metrics` 也照常可用 | MUST |
| P19.9 | 外壳声明自己的 `deployment.stopGracePeriodSeconds`（brickKit 原样使用，不从成员推），不小于它编进来的任何成员的值；它自己的 `SHUTDOWN_GRACE` 不小于成员里最大的。收到 SIGTERM 并行停所有成员（CP-SHELL-11） | MUST |
| P19.10 | 外壳声明 `readinessCheck: {type: http, path: /readyz}`；它的 `/readyz` 只在所有被承载成员都就绪时答 200，否则 503 `NOT_READY`，`metadata.waiting` 列出没就绪的成员 ID；零个成员时 200（CP-SHELL-11） | MUST |

外壳打开每个成员的端口，所以部署条目可以 `expose` 成员（brickKit ≥ v1.2，be-protocol P19 正文）：Docker / Podman 上外壳容器映射成员的主端口；K8s 上成员有自己的 Ingress，指向选中外壳 Pod 的成员 Service。成员条目上的 `replicas`、`resources`、`labels` 不生效，所以边缘的 Traefik 标签由 be-ops 同时写到外壳条目上（foundations 18）。成员的密钥文件挂在外壳容器里同一路径。

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
| P20.4 | `GET /_be/info` 符合 `info.schema.json`，并与镜像的清单（ID、版本、端口）一致；其中 `profiles` **必须等于**套件按清单选出的那一组（§4.3），多一个少一个 CP-CORE-11 都失败 | MUST |
| P20.5 | `component.yaml` 声明 `release: {checks: [[make, conformance]]}`（brickKit ≥ v1.4.0）：`brickkit release`（以及 `publish`、`release --local`）对发版提交跑本组件的一致性套件，失败就拒绝打 tag（`RELEASE_CHECK_FAILED`）；用 `--skip-checks` 跳过时会被打印出来。widget 夹具声明了它（§4.6） | SHOULD |

---

## 3. 规范放在哪、怎么版本化

### 3.1 仓库 `brickKit/be-protocol`（新建，需用户同意，§9 Q1）

```
be-protocol/                     （实际布局，以仓库为准；裁决 ab）
  README.md  README.zh.md        是什么、怎么读、版本规则
  CHANGELOG.md  CHANGELOG.zh.md  LICENSE
  spec/00-reading-the-spec.md … 20-self-description-and-versioning.md   正文，英文为准；同目录 NN-x.zh.md 是中文镜像，同样的 ## 小节
  schemas/  config-keys.yaml       协议级配置键：名字、类型、是否密钥、默认值、属于哪个 profile（P2）
            errors-be.yaml         SDK 保留的 reason（P4）
            problem.schema.json  envelope.schema.json  events-contract.schema.json
            lifecycle.schema.json  data-lifecycle-config.schema.json  jobs-overrides.schema.json
            errors-yaml.schema.json  assembly-protocol.schema.json  info.schema.json  access-token.schema.json
            fixtures.schema.json  conformance-cases.yaml / .schema.json  compconf-report.schema.json
  ddl/      01-platform-version.sql … 10-lifecycle-functions.sql、be_bus.sql   平台表与平台函数的参考 DDL（规范性，附录 A 的定稿）
  proto/be/v1/limits.proto         extend FieldOptions { int32 max_items = 51001; }
        be/lifecycle/v1/           gRPC be.lifecycle.v1.Lifecycle
  openapi/  resource-authz.yaml (_authz/check|explain, _shares)
            resource-lifecycle.yaml (_lifecycle/*)
            ops.yaml (/healthz /readyz /_be/info /_ops/jobs)
  vectors/  calendar/ config/ envelope/ errors/ idempotency/ money/ numbering/ redaction/ …   全协议通用的语义向量
            SHA256SUMS                       （族的判定向量不在这里，在族契约仓库，§1 第 17 条）
  fixtures/widget/  fixtures/peer/  夹具组件和假对端的契约与行为说明（apis 文件 §6）
  fs.go  go.mod                    唯一的代码：//go:embed 把 schemas、vectors、ddl 导出成 fs.FS，供 be-acceptance 和 be-sdk-go 的测试用
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

- `docs/{en,zh}/04-foundations/` 新增一篇 `02-languages-and-component-protocol.md`（**已写**，D3a）。按 foundations 的 11 个固定小节写：
  - Choice：协议加黑盒套件，SDK 是参考实现。
  - Alternatives：
    - 锁死语言（即今天的 0105）；
    - sidecar（Dapr）：外壳里只能有一个 app-id，成员身份丢失；
    - WASM 组件模型：生态不成熟，PG / gRPC 驱动缺；
    - 每门语言各自约定、不做黑盒测试：漂移无法发现。
  - When to switch：出现必须跨语言合进一个进程的需求，这一条永远不支持，写成 Known limits。
  - 仓库已建（`tools/be-protocol`，子模块）。正式文档链到它的 GitHub 地址（外部链接不受 `docs-boundary` 约束）；rc 阶段名字以仓库为准，文档与仓库说法不一致时改文档（裁决 ab）。
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
 │    PG：make up 的实例，库 brickkit_test_db；每次运行现建随机 schema + 随机的属主角色（拥有 schema）和运行角色（只有 USAGE + DML）
 │        + 一个 NOINHERIT 的"外壳"角色（PG16，WITH INHERIT FALSE, SET TRUE）；跑完全部删掉（同 besdktest）
 │    NATS：每次运行起一个一次性的 nats-server -js 容器，流和 durable 不和开发环境相撞
 ├─ 假服务（套件进程内）：
 │    fake-iam    JWKS + 签发器：签 access / refresh / 错 iss / 错 aud / 无 exp / HS256 / 轮换后的钥匙 …
 │    fake-authz  contract-infra-authz v2：bundle（每条用例脚本化）、changes、ReadTuples、Check、WriteTuples、poke
 │    fake-peer   被测组件的每个依赖：gRPC 从依赖的 proto 描述符动态应答（protoreflect），
 │                用户面 HTTP（UserHTTP 的对端）按 fixtures 的样本应答（S-b 裁决 au，A1 再做）；
 │                记录 metadata、截止时间、连接数；可以挂起、返回 UNAVAILABLE、变慢
 │    otlp-sink   OTLP/HTTP 接收器，按 trace_id 收 span
 └─ 被测容器：先 migrate（两次），再 serve（1 个或 2 个副本）；外壳模式下按 BRICKKIT_SERVED_MEMBERS_CONFIG 起
```

套件给被测容器的配置：

- 先取 `configSchema` 的默认值；
- 再盖上套件的值：随机的 PG 身份（口令写进套件挂给容器的 `_FILE` 文件，和 brickKit 的挂载同一路径，环境变量里只有路径）、`AUTHZ_URL` / `AUTHZ_GRPC_URL` / `IAM_URL` / `IAM_GRPC_URL` / `TENANT_ID` 指向假服务、依赖的 `*_ENDPOINT` 指向 fake-peer、`OTEL_BASE_URL` 指向 otlp-sink；
- 再盖上加速用的键：`EVENTS_BACKOFF=200ms,500ms,1s`、`EVENTS_MAX_DELIVER=3`、`GRPC_MAX_CONNECTION_AGE=10s`、`JOBS_OVERRIDES`；
- 组件自己的必填键，取 `fixtures.yaml` 顶层 `config` 里给的值。

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
| `auth` | 有任何非 Public 路由（缺 `x-be-permission`、又没标 `x-be-internal: true` 的 operation 按受保护的算，P3.16） | 13 |
| `scope` | `data_scopes` 不是 `none`，或声明了 `resources` | 15 |
| `grpc` | 有名为 `grpc` 的 extraPort | 6 |
| `outbound` | `dependencies.components` 非空 | 8 |
| `events-pub` | `contracts/events` 里有本组件发布的 subject | 5 |
| `events-sub` | 订阅了任何 subject（fixtures 里列出） | 7 |
| `idempotency` | 任何写操作带 `idempotency_key` / `Idempotency-Key` | 8 |
| `db` | `configSchema` 里有 `PG_SCHEMA` 或 `PG_HOST`（P2.8 的触发键） | 4 |
| `jobs` | 有库（平台任务一定存在） | 5 |
| `lifecycle` | 有库 | 4 |
| `blob` | `configSchema` 里有 `S3_BUCKET` 或 `S3_URL` | 3 |
| `shell` | `component.yaml` 有 `shell.members` | 10，外加对每个成员在外壳模式下重跑它的 profile |

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

fixtures 的完整字段以 be-protocol `schemas/fixtures.schema.json` 为准。S-b 写 widget 夹具时补进去的字段（裁决 at）：面向用户的 rpc（测 CP-RPC-03）、锁的目标（CP-DB-02）、会把个人数据写进日志的路由（CP-OBS-04）、维度和排序参数（scope、`SORT_FORBIDDEN`）、生命周期的范围参数（`RANGE_COLD`）、blob 用例、cron / reconciler 的触发方式、handler 产生的事件、HTTP 依赖的键。夹具里的资源类型名一律写全名，例如 `conformance.widget.widget`（裁决 av）。rc.2 再加两个字段：`operation.paired_with`（`resources.<res>.<op>`：同一资源、同一代码路径上对应的 REST / gRPC 操作，CP-ERR-02 拿它们比对）；顶层 `config`（套件给组件自己的必填键设的值）。用例目录 `conformance-cases.yaml` 的每条用例可以带 `applies_when`：CP-ERR-02 只在组件有 `grpc` 端口时、CP-ERR-03 只在组件有库时适用，不适用就记"not applicable"，既不算跳过也不算失败。

`observe.sql` 读的是被测组件**自己 schema 里的表**。套件拥有这个库，所以能直接查，这不算偷看代码。没有公开读接口的消费效果（快照、台账）就靠它观察。

### 4.4 用例目录（代表性用例，ID 稳定，只增不改）

| profile | 用例 |
|---|---|
| core | 01 迁移连跑两次都是 0 退出；02 缺必填键或类型错 → 退出码 78，日志点名键；03 PG / NATS / authz 晚于组件就绪 → 组件不退出，依赖就绪后恢复；04 停掉 PG 后 `/healthz` 仍是 200；05 `/readyz` 语义（MUST，就绪后锁定）；06 SIGTERM → 在宽限期内以 0 退出（在途请求完成只在 fixtures 声明了 `slow` 时检查，否则只看退出码和退出用时）；07 镜像里有 sh 和 wget；08 慢速请求头被断开；09 超过请求体上限 → 413（带 `Expect: 100-continue` 发、会重试）；10 `X-Request-Id` 回写，缺失时生成；11 `/_be/info` 与清单一致，`profiles` 等于套件选出的那组；12 `component.yaml` 声明 `healthCheck`、`readinessCheck`、`stopGracePeriodSeconds` ≥ `SHUTDOWN_GRACE` + 5 s、端口 `protocol`；13 容器里 `127.0.0.1` 和 `::1` 都能答 `/healthz`；14 每个密钥键都是 `mount: file` 且以 `_FILE` 命名，环境变量里没有密钥的值，换掉的密钥文件不重启就用上 |
| obs | 01 入站带 `traceparent` → otlp-sink 看到的 span 以它为父；02 日志字段齐全，访问日志带 `trace_id`；03 `/metrics` 的名字、`component` 标签、`route` 是模板；04 PII 键被脱敏；05 `LOG_LEVEL=warn` 时没有 info 行 |
| err | 01 每个 4xx 都是 problem+json，`reason` 在 errors.yaml 或 errors-be.yaml 里；02 gRPC 错误带 ErrorInfo，并能与 REST 互相还原（按 `paired_with` 配对，只在有 `grpc` 端口时适用）；03 运行中套件收回某张表的权限 → 500 只有通用文案 + `trace_id`，响应里没有 SQL 原文（只在有库时适用）；04 出现过的每个 reason 都登记过 |
| auth | 01 没有 token → 401；02 `alg: none` / HS256 / 没有 kid → 401；03 刷新令牌 → 401；04 iss 不对；05 aud 不对；06 没有 exp；07 JWKS 轮换、不认识的 kid 触发刷新；08 stale → 401 `token_stale`；09 openapi 里的每个操作都有守卫，不带 token 时非 Public 的一律 401；10 还没拿到 bundle → 每个非 Public 路由（含 Authenticated）503 `AUTHZ_NOT_READY`，没 token 仍先 401；11 缺键 → 403 `MISSING_PERMISSION`；12 委托能力不足（`act.kind=agent` 而 `agents=false` 等）→ 401 `UNSUPPORTED_DELEGATION`；13 拿到 bundle 后停掉 authz → 照常判定（fail-static） |
| scope | 01 own / dept / subtree / all 四档矩阵；02 按键求值；03 维度取值和 `*`；04 `until` 到期；05 多个角色取最高档；06 R60：没有部门的人只看到自己的；07 看不见的单条读 → 404；08 对看不见的记录发命令 → 404；09 看得见做不了 → 403，维度参数越权 → 403 `OUT_OF_SCOPE`；10 **List/Can 一致**（随机授权组合的属性测试，比对列表和 `_authz/check`）；11 字段掩码、按掩码字段排序被拒；12 `_authz/check` 的形状和上限；13 explain 不泄露看不见的记录；14 `sharing=false` 时 `_shares` 答 501；15 changes 下发共享 → 6 s 内可见，带 `X-Authz-Revision` 时立刻可见，撤销后不可见 |
| grpc | 01 没有 `be-caller` → `UNAUTHENTICATED`；02 系统调用的日志带 `caller`；03 面向用户的方法经 gRPC → `UNAUTHENTICATED`；04 5 MiB 请求被拒；05 `MaxConnectionAge` 之后发 GOAWAY，客户端透明重连；06 BatchGet 超上限 → `BATCH_TOO_LARGE` 加 BadRequest |
| outbound | 01 触发 50 次 → fake-peer 只看到 1 条连接；02 出站的 `grpc-timeout` ≤ 3 s，且小于入站剩余；03 只对幂等方法在 UNAVAILABLE 时重试；04 一直 UNAVAILABLE 时，重试量 ≤ 10 %；05 对端挂起、并发超过 64 → 立刻 `OUTBOUND_LIMIT`；06 `UserHTTP` 转发 Authorization、`x-request-id`、`traceparent`；07 对端挂起 → 组件在路由截止时间内答 504，不跟着挂死；08 出站带 `be-caller`、`be-actor-sub`、`traceparent` |
| events-pub | 01 命令 → 流上出现事件，`ce-*` 头齐全，`ce-id` 是 UUIDv7 且等于 `Nats-Msg-Id`，`aggregatetype` 与契约一致，`traceparent` 和请求同一个 trace；02 停掉总线 → 命令照样成功 → 恢复总线 → 恰好送达一次；03 两个副本 → 每行 outbox 只发布一次；04 没有流就按默认值建，已有的流配置不被覆盖；05 payload 通过契约校验，超过 64 KiB 的在发布时被拒 |
| events-sub | 01 durable 的名字和参数；离线期间发布的事件，上线后补收；02 重复投递只生效一次；03 乱序（v3 先于 v2）的最终状态与按序相同（属性测试）；04 格式错误的 payload → DLQ，带 `be-dlq-*` 头；05 临时失败（套件暂时收回表权限）→ 按 `EVENTS_BACKOFF` 延迟重投 → 恢复后生效；handler 耗时 > AckWait/2 且持续发 InProgress → 只执行一次；06 handler 里发出的事件带 `causationid` 且 `hopcount` + 1，`hopcount=11` 的入站事件进 DLQ；07 交易单据事件缺法人 → DLQ |
| idempotency | 01 重放返回首次结果；02 换请求体 → 400 `IDEMPOTENCY_MISMATCH`；03 换 target；04 换命令；05 两段式命令进行中 → 409 `IDEMPOTENCY_IN_PROGRESS`；06 不同 caller 同一个键互相独立；07 并发同键只执行一次；08 请求头和 body 等价，冲突时 400 |
| db | 01 随机身份下全部 profile 照常通过，表的属主全是 `PG_OWNER_USER`，运行角色没有 CREATE、不是属主的成员，schema 外没有任何对象；02 套件持锁 → 组件在 `lock_timeout` 内答 409 `LOCK_TIMEOUT`；03 压满并发 → 该角色的连接数 ≤ `PG_POOL_MAX`；04 `besdk_*` 表与参考 DDL 逐列一致（查目录比对）；`besdk_authz_acl` / `besdk_authz_cursor` 恰好在声明了 `resources` 时存在 |
| jobs | 01 两个副本，平台 Cron（`be.cleanup`，用 `JOBS_OVERRIDES` 改成 `@every 2s`）每个槽只跑一次；02 Singleton（生命周期引擎）同一时刻只有一个持有者，杀掉持有者后另一个在 TTL 内接管；03 Queue 的作业在两个副本下只执行一次（fixtures 给出会入队的命令）；04 业务事务回滚 → 作业不存在；05 运行中 `pg_terminate_backend` → 任务失败后被重启，进程不退出 |
| lifecycle | 01 新库迁移后立刻能写入（分区窗口已就绪）；02 早于在线下界的范围 → `RANGE_COLD`；03 `_lifecycle/*` 都已挂出，未实现的答 501；04 `lifecycle.yaml` 通过 schema 校验，覆盖了全部表 |
| blob | 01 预签名 PUT 带内容长度上限；02 bucket 不可匿名读；03 预签名有效期 ≤ 5 min |
| shell | 01 出现没编译进来的成员 → 非 0 退出并点名；02 成员版本不符 → 非 0 退出；03 成员的 `PG_HOST` 或 `AUTHZ_URL` 与外壳不同 → 拒绝启动；04 每个成员的 span，`service.name` 是成员 ID；汇总的 `/metrics` 带 `component` 标签；05 一个成员把连接预算耗尽，另一个照常；两个成员订阅同一个 subject 各收一份；06 成员的后台任务失败后被重启；07 NOINHERIT 的登录角色下，四类后台路径全部正常；08 对每个成员按外壳模式重跑它自己的 profile；09 跑完 HTTP → gRPC → 事件链路后，收集器里没有 `service.name` = 外壳 ID 的 span；10 先停一个成员，另一个成员之后发的 span 不丢（R1 #1） |

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

- `make conformance`：每个组件和外壳的仓库里都有这个目标（父项目里是 `make conformance ID=<组件> [SHELL=<外壳>]`），构建镜像后对它跑一遍套件（几分钟级），产出报告（§4.5）。
- **发版由平台把关**（P20.5，brickKit ≥ v1.4.0，FR06-028）：组件和外壳在 `component.yaml` 里声明
  ```yaml
  release:
    checks:
      - [make, conformance]
  ```
  `brickkit release`（以及 `publish`、`release --local`）对发版提交跑这些检查，任何一项失败就拒绝打 tag（`RELEASE_CHECK_FAILED`）；用 `--skip-checks` 跳过时会被打印出来。所以"先过 compconf 再打 tag"不再靠技能文档约束；widget 夹具也这样声明。
- 门禁 **`compconf-record-scan`** 保留，但**收窄**，仍进 `make gates`，离线、很快：
  - 钉住版本的清单里声明了带 `[make, conformance]` 的 `release.checks` 的组件或外壳，**不再要求**项目里有报告：brickKit 不让它在套件失败时打 tag；
  - 没声明这项检查的（别家的组件、去掉了这项检查的分叉），仍要求项目里存一份对应**精确版本**的全绿报告：报告里的镜像摘要等于本地镜像（本地没有镜像时只警告）；套件版本不低于 be-acceptance 要求的最低版本；必测 profile 全部 pass，skip 都有理由；
  - 它守的正是 `release.checks` 管不到的东西：项目自己不发版的组件。
- `version-bump-ship` 技能和 `make ship` 里的发版一步就是 `brickkit release`（它会跑 compconf）：裸 tag 由它打，Go 的 `v` tag 和生成契约包的 tag 仍由 ship 脚本打，并且 `brickkit release` 在推这些 tag 之前跑；发版之后再核对一次工作区是干净的；ship 脚本从不传 `--skip-checks`（测试里断言）；项目门禁仍在 ship 的第一步（阶段 B 第二波的控制者安排）。只有上面"没声明检查"的组件，才需要另跑 compconf、把报告和组件指针一起提交。镜像变了，就必须重跑。
- 第四门语言的组件，走完全相同的路径：声明同样的 `release.checks`，仓库里提供 `make conformance`。

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
| 组件声明 | `besdk.Spec{ID, Manifest, Migrations, Contracts, Catalog, ErrorDomain, New}` | `besdk.Spec(id=, migrations=, contracts=, create=, manifest=, error_domain=)` | `defineComponent({id, migrations, contracts, manifest, errorDomain, create})`（`ComponentSpec`） |
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
| 事件声明 | `besdk.Events{Publishes, Subscribe: []besdk.Subscription}`（`Subscription` 可选 `AggregateType`） | `besdk.Events(publishes=, subscribe=)` | `{publishes, subscribe}` |
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
| 运行时 | Go 1.25 | **CPython 3.14**（基础镜像 `python:3.14-slim`；R1 #10 实测 asyncpg、grpcio、pyarrow 在 8 个平台组合都有 wheel，裁决 bb） | **Node 24 LTS** |
| HTTP | Gin | FastAPI on uvicorn（一个进程、一个事件循环） | **Fastify 5**（≥ 5.12，要有 `handlerTimeout`；BFF 的 GraphQL 用 graphql-yoga 5，挂在 Fastify 上；实例选项见 apis §4，R1 #8，裁决 ba） |
| gRPC | grpc-go | grpc.aio | **@grpc/grpc-js** + ts-proto 生成代码（`outputServices=grpc-js,esModuleInterop=true,outputSchema=true,importSuffix=.ts,enumsAsLiterals=true`；`outputSchema` 让 SDK 在运行时读到 `idempotency_level` 和 `max_items`，`enumsAsLiterals` 避开 Node 24 类型擦除不支持的 TS `enum`，R1 #3、r1-03b） |
| 数据库 | database/sql + pgx/v5 stdlib，sqlc，手写 SQL | `asyncpg==0.31.0`（0.30.0 没有 cp314 wheel），手写 SQL，Pydantic 映射行 | **pg（node-postgres）8**，手写 SQL，zod 校验行 |
| 迁移 | golang-migrate，纯 `.sql` | yoyo-migrations，纯 `.sql`（入口收进 SDK），同步驱动 `psycopg[binary]==3.3.6`（`postgresql+psycopg://` 后端） | **node-pg-migrate**，纯 SQL 文件；必须显式传 `ignorePattern`、由 schema 派生的 `lockValue` 和 `advisoryLockMode: 'wait'`（R1 #6） |
| 事件 | nats.go `jetstream` | nats-py JetStream | **@nats-io/jetstream** + transport-node |
| 十进制 | cockroachdb/apd/v3 | 标准库 `decimal` | decimal.js |
| JWT | golang-jwt/v5 + keyfunc/v3 | PyJWT（必须传 `audience`） | jose 6 |
| 出站 HTTP | net/http | httpx | undici（按依赖一个 Agent） |
| 事件 payload 校验（JSON Schema） | santhosh-tekuri/jsonschema/v6 | `jsonschema==4.26.0` | **AJV** |
| 日志 / 指标 | slog / client_golang，每个模块一个 registry | logging（SDK 的 JSON formatter）/ prometheus-client，每个模块一个 CollectorRegistry；Meter 经 `opentelemetry-exporter-prometheus==0.59b0` 写进它 | pino / 保留现用的 Prometheus 客户端，每个模块一个 Registry |
| trace | otel-go + otelgrpc | opentelemetry-python + grpc 拦截器 | @opentelemetry/sdk-trace-base；**不用 auto-instrumentation**（它全局打补丁，会破坏"每个成员一个 provider"） |
| 对象存储 | aws-sdk-go-v2 | aioboto3 | @aws-sdk/client-s3 |
| UUIDv7 / 拼音 | google/uuid / go-pinyin | 标准库 `uuid.uuid7`（3.14 起有，不再依赖 uuid6）/ pypinyin | uuid 11 / pinyin-pro |
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
  - 需要在每个事务里 `SET LOCAL ROLE` / `search_path` / 超时。porsager 默认隐式缓存预编译语句，和"同一条连接上切换 search_path"有交互风险（R1 #4 已证实：缓存键不含成员 schema 时形状不同就报错），只能靠关缓存规避。
  - Kysely 和 Drizzle 是查询构造器或 ORM，Prisma 是 ORM 且带独立引擎，都和 0103 的"手写 SQL、不用 ORM"冲突。Prisma 还做不到每个事务 `SET LOCAL ROLE`。
  - node-postgres 的池参数（`max`、`connectionTimeoutMillis`、`idleTimeoutMillis`）、LISTEN/NOTIFY（pgqueue 的 Notify 要用）、COPY 流，都现成。
- **node-pg-migrate**：支持纯 SQL 文件，状态表可以放进本组件的 schema（`--migrations-schema`），拿锁也是独占连接。Graphile Migrate 绑定了自己的开发流程；dbmate 是一个 Go 二进制，塞进 Node 镜像很别扭。
- **grpc-js，而不是 connect-node**：connect-node 不支持服务配置里的重试和重试预算，服务端也没有 `MaxConnectionAge`，协议 P7.5 / P7.8 做不到。grpc-js 是唯一一个维护中的纯 JS gRPC 实现。ts-proto 能生成 grpc-js 的服务定义，以及 `google.rpc.*` 错误详情的类型。
- **要先做最小复现再铺开**（照记忆里的教训）：
  - grpc-js 的 service config 里，`retryPolicy` 和 `retryThrottling` 是否真的生效；
  - node-pg-migrate 在指定 schema、不建 schema、不写 OWNER 时的行为；
  - 每个成员一个 `BasicTracerProvider`、共用一个导出器，在 Node 上是否可行；
  - pg 池在 `SET LOCAL` 之后归还连接时是否干净。

  这几条列为 §7.7 的任务 R1，结果见 §7.9：grpc-js 的重试生效但预算按进程（#3）；node-pg-migrate 要显式传三个选项（#6）；pg 池归还时干净（#4）。Node 上"每个成员一个 provider"没有单独复现，按 Go 的结论（#1）实现，由 compconf 的 CP-SHELL-09 / -10 守住。

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
2. **门禁**：扫源码的门禁（`bare-route-scan`、`identity-literal-scan`、`import-scan` 等）只认官方语言，对第四门语言不适用。替代它们的是 compconf（经 `release.checks` 接在 `brickkit release` 上，§4.6），加上评审时按 apis 文件 §7 的 INTERNAL 清单逐条核对。没声明 `release.checks` 的，`compconf-record-scan` 照常要求报告。
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
| 1 | `protocol-config-scan`、`events-declaration-scan` | configSchema 的协议键段等于 be-ops 按 `config-keys.yaml` 生成的结果（类型、默认值、`secret`、`mount: file`）；`secret: true` ⇔ `mount: file` ⇔ `_FILE`；不再出现 `AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`、不带 `_FILE` 的密钥键；`events:` 段等于按事件契约和 fixtures 生成的结果；`deployment.stopGracePeriodSeconds` ≥ `SHUTDOWN_GRACE` + 5 s、外壳的值不小于成员的 | B 结束 |
| 2 | `migration-identity-scan`、`identity-literal-scan` | data-layer §2.6；外加禁止 `BIGSERIAL` 主键、禁止 `NUMERIC(18,2)` 金额列（`id-type-scan`、`money-precision-scan` 并入这里） | C 开始（新基线一律报错） |
| 3 | `platform-table-scan` | 组件的 SQL 不碰 `besdk_*`；不手写 inbox、幂等、游标的 SQL（取代 events-consistency §6 第 6 条） | C 开始 |
| 4 | `lifecycle-scan` | data-lifecycle-v2 §5.3 | C 开始 |
| 5 | `business-date-scan` | SQL 里出现 `CURRENT_DATE` / `now()::date` / `date_trunc(…, now())` 就报错 | C 开始 |
| 6 | `batch-cap-scan`、`idempotency-level-scan` | data-layer D8；foundations-communication §5.7 | C 开始 |
| 7 | `error-catalog-scan` | `contracts/errors.yaml` 存在且格式正确；官方语言的代码里用到的 reason 都登记过 | D 开始 |
| 8 | `authzgen-fresh`、`authz-capability-scan`、`perm-key-usage-scan` | authz-architecture §5.4、identity §3.3g | D 开始 |
| 9 | `module-ticker-scan`、`module-global-cache-scan`、`besdktest-import-scan` | 模块里不许自己写循环、包级缓存；生产代码不许 import 测试包 | D 开始 |
| 10 | `sdk-version-scan` | 扩展 `dependency-version-scan`：同一门语言的组件和外壳钉同一个 SDK 版本；外壳等于它成员的版本 | E 开始 |
| 11 | `compconf-record-scan` | §4.6（收窄）：钉住版本的清单声明了 `release: {checks: [[make, conformance]]}` 的组件和外壳免报告（`brickkit release` 已在套件失败时拒绝打 tag）；没声明的（别家的组件、去掉检查的分叉）要求项目里有精确版本、镜像摘要相符、必测 profile 全绿的报告 | 对 3.0.0 及以上的组件一律报错 |
| 12 | `connection-budget-scan` | 所有进程的 `PG_POOL_MAX` 之和，加上迁移和 Casdoor 的预留，小于 `max_connections` 减去保留 | E 开始 |
| 13 | `edge-routes-fresh` | 部署文件里 be-ops 生成的 `paths` / Traefik 标签与 `edge_routes` 一致；OpenAPI 路径都在声明的前缀之下（foundations 18） | E 开始 |
| 后来 | `contract-migration-scan`、Squawk | foundations-data-platform §6.4 | 06c 之后 |

**改**：

- `bare-route-scan` 认新的路由写法：Go 的 `besdk.GET`、Python 的 `@r.get`、TS 的 Fastify `r.get`；
- `data-scope-test-scan` 认 404；
- `dependency-version-scan` 支持 `/v3`。

**退役**：`system-client-scan`（identity §5.3：它的前提不成立）；`service-hostname-scan`（族地址改成 `$endpoint:` 引用，没有手写服务名可核对了，bk1）。

**versionbump 工具**：要支持主版本跳到 `/v3`（改模块路径、改全部 import、改外壳的 `go.mod`），这是任务 A9。

### 7.4 每个组件 3.0.0 的统一清单

1. **依赖**：SDK v0.6.0。Go 的模块路径改成 `/v3`。
2. **重建迁移基线**：删掉旧迁移，写一份新的 `0001_init`：
   - 主键用 `uuid`（UUIDv7）；
   - 金额、单价、数量按 P11.6 的精度，金额与币种成对；
   - 交易单据带 `legal_entity_id`；
   - 业务日期是 `DATE` 列；
   - 不出现 `OWNER TO`、日期分区、`_rw`；迁移以 `PG_OWNER_USER` 跑，运行时只用 `PG_USER`；
   - 平台表**不写**进组件的迁移，由 SDK 的平台迁移负责。

   这一条需要决策 0305 明文破例（§7.6）。
3. **`lifecycle.yaml` v1**，初稿见 data-lifecycle-v2 §6.1。
4. **模块改写**：
   - `Spec` / `Module`；
   - `Store`；
   - 声明 `Events`（`component.yaml` 的 `events:` 段由 be-ops 生成，P12.16）；
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
   - be-ops 把资源契约片段并进组件的 openapi（放在 be-ops 的标记注释之间，widget 夹具的 OpenAPI 就是这样）；
   - 每个 operation 带 `x-be-permission`，提供方平面 / 运维端点标 `x-be-internal: true`（P3.16）。
6. **`assembly.yaml`**：`protocol: "1.0"`、`resources`、`requires_capabilities`、`type: field` 的键、`conformance.fixtures`。`.admin` 键在 `permissions.tsv` 里标 deprecated（只增不删）；可委托的键在新追加的 `delegable` 列里标出。
7. **配置**：
   - configSchema 的协议键段由 be-ops 按 `config-keys.yaml` **生成**（O1），不手写；
   - 每个用到的 profile 手写一个触发键（`db`：`PG_SCHEMA` 或 `PG_HOST`；`blob`：`S3_BUCKET` 或 `S3_URL`），其余由 be-ops 补齐（P2.8）；
   - 新增 `PG_OWNER_USER` / `PG_OWNER_PASSWORD_FILE`（属主与运行角色分开，F27）、`AUTHZ_URL`、`IAM_URL`、`IAM_ISSUER`、`TENANT_ID`、`EVENT_BUS_URL`、`DATA_LIFECYCLE`、`DEFAULT_LOCALE`、`DEPLOY_ENV`、池的几个键（没有 `PG_POOL_MIN_IDLE`，它已退役）；`PG_SCHEMA` 不超过 40 个字符；调 authz rpc 的加 `AUTHZ_GRPC_URL`，调 iam 目录的加 `IAM_GRPC_URL`；用对象存储的加 `S3_PUBLIC_URL`（法人日历来自 mdm/org，不是配置键）；
   - 每个密钥键改成 `_FILE` + `mount: file`（`PG_PASSWORD_FILE`、`S3_ACCESS_KEY_ID_FILE`、`S3_SECRET_ACCESS_KEY_FILE`，组件自己的密钥也一样，P2.12）；`config/` 里的值照旧写 `${VAR}` / `file://`；
   - 删掉 `AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`；
   - `component.yaml` 加 `readinessCheck: {type: http, path: /readyz}`、`deployment.stopGracePeriodSeconds: 30`、主端口 `deployment.protocol: http`、gRPC 端口 `protocol: grpc`（P1.11–P1.13），以及 `release: {checks: [[make, conformance]]}`（P20.5，brickKit ≥ v1.4.0）；仓库的 Makefile 提供 `conformance` 目标；
   - 事件契约里的 poke 标 `x-signal: true`（P12.10）；走 pgqueue 总线的组件声明 db 的键（P12.12）；
   - `config/vars.yaml` 在同一批里一起改：族地址写成 `$endpoint:` 引用（`AUTHZ_URL: $endpoint:infra/authz` 等四个键），不再手写服务名（取代"核对 `service-hostname-scan`"，记忆里的 C18 从此不会再发生）。
8. **测试**：
   - 改用 `besdktest`，每个连库测试都在随机身份下跑；
   - 每个消费者一条"乱序加重复的终态等于按序"的属性测试；
   - 前文列出的本组件红测试先提交、先跑红。
9. **文档**：BRICKKIT（"Before you deploy"写通用表述，加一节"数据与保留"）、AGENTS、design.md，中英两份。
10. **种子数据**：
    - id 全换成 UUIDv7；
    - 加第二个法人「本地测试」华南子公司；
    - 首个管理员改用共享变量 `BOOTSTRAP_ADMIN_LOGIN`（I4 的实现，裁决 r：平台 `sub` 首次登录前不可知，所以按 IdP 登录名或邮箱，首次登录时绑定）；
    - `db-reset` 之后重新播种。
11. **发版与验收**：`brickkit release`（经 `release.checks` 跑 compconf，不过就不打 tag；Go 组件另打 `v3.0.0`）→ `brickkit upgrade` → `make verify` → `brickkit down`（记忆：验证完一定要关）。

### 7.5 各组件特有的改动（汇总前文，版本统一是 3.0.0）

| 组件 | 特有改动 |
|---|---|
| infra/authz | v2 provider 的 P0 部分：档位（含 `dept`）、维度取值、字段键、能力、revision。ResolveClaims v2 带 `tenant_id`。审计事件走 outbox，带 actor。改部门写 stale。superuser 自动补齐键；系统角色和最后一个管理员受保护。`/api/me/access` v2。元组表和 changes 端点的形状一次建齐，`sharing` 能力随 P1 打开。`provides_capabilities`、`RESOURCE_CATALOG`、`DATA_SCOPE_CATALOG` |
| infra/iam-casdoor | 删掉对 authz 的依赖边，改读 `AUTHZ_URL`。签 `typ`、`iss`、`aud`、`jti`、`tenant_id`、`locale`。平台 `sub` + `identity_links`。`/api/iam/login-config`。按 RFC 8693 的形状换 token（`casdoor_id_token` 留作别名，直到 06c 的前端改掉）。建 Casdoor 应用时 `tokenFormat: JWT-Standard`（今天 `admin.go:293` 写的 `JWT` 会把 86 个 claim、含 `passwordSalt`、`totpSecret` 的整条用户记录塞进 token，R1 #9，裁决 ag 待用户定是否先发 2.0.1），`grantTypes` 只要 `authorization_code`；拒收 IdP 标为 refresh 的 `subject_token`、要求 `kid`。`IAM_ISSUER` 是稳定的 URN `urn:be:<tenant>:iam`，元数据在 `IAM_URL` 下；token 错误是 problem+json，带 `metadata.oauth_error`；`enabled_components` / `GetTenantFeatures` 移到 authz 的 `/api/me/access`（K2）。`BOOTSTRAP_ADMIN_LOGIN` 在首次登录时绑定。`User` 加 `version` 和 `disabled`；新增 `deleted` 事件。webhook 投递改成 `Queue` / `Reconciler`。登录调 authz 带上截止时间 |
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
- **0107**：只剩 `AUTHZ_URL`；新增 `IAM_ISSUER`、`TENANT_ID`。第二次改写（bk1，已落笔）：族地址是 `config/vars.yaml` 里的 `$endpoint:` 引用，四个键 `AUTHZ_URL`、`AUTHZ_GRPC_URL`、`IAM_URL`、`IAM_GRPC_URL`，不做端口算术，`IAM_JWKS_URL` 和 `service-hostname-scan` 退役。
- **0508**：记下 FR06-007 的结论（不做，引本决策为推荐做法）和可选的"跑一次"入口（已落笔）。
- **0509**：路由生成进部署条目（`paths`、Traefik `labels`），以路径段为界（已落笔）。
- **0104**：槽位族地址用 `$endpoint:`（已落笔）。
- **0201**：没有缓存服务器，缓存经 `besdk.Cache`。
- **0202 / 0203 / 0204 / 0205 / 0206**：authz-architecture §6.3。
- **0301**：金额的精度、金额与币种成对。
- **0102**：Revisit 补上"每个成员一个池"（方案 C）和 Citus；去掉每组件的 `_archive` schema，冷数据进组件自己 bucket 的 `cold/<table>/…`（裁决 l、c）；属主角色与运行角色分开（F27，裁决 p）。

**新增**

| 位置 | 决策 |
|---|---|
| 01-architecture **0109** | 组件协议加黑盒一致性测试；官方 SDK 是参考实现；不允许 SDK 里有规范没写的行为（§3.2） |
| 02-permissions 0207–0211 | authz-architecture §6.3 |
| 03-contracts-and-data 0304 | BatchGet 有上限，上限是契约的一部分（D8） |
| 03-contracts-and-data **0305** | 3.0.0 的一次性破例：已发布的迁移可以整体替换为新基线，前提是**没有生产数据**。写明判据和"仅此一次"；以后同样的情况要重新拍板 |
| 03-contracts-and-data 0306–0308 | 主键用 UUIDv7、单据号由 SDK 分配；业务日期与法人日历；租户 = 部署，法人是维度（F1–F5） |
| 05-runtime 0501–0508 | foundations-communication §11.3：事务里不发网络调用；隔离与重试；截止时间与重试预算；错误模型与 reason 登记表；CloudEvents 信封与聚合流游标；至少一次送达与建流；后台工作只经 Jobs |
| 05-runtime **0509** | 边缘只路由，认证和授权留在每个服务里（裁决 q；foundations 18 链它）。其余未编号的（进程归启动它的组件、有界表不分区、审计走 outbox、边缘路由由声明生成等）仍标"计划中"（裁决 s） |

**约定**

| 文件 | 改什么 |
|---|---|
| `02-backend.md` | 整篇重写成"用官方 SDK 写组件"，每节链到对应的 P 章节；新增"用其它语言写组件"一节 |
| `04-configuration.md` | 共享键表（P2）；Database roles 一节按 R63 改写 |
| `06-testing.md` | 测试层次加上"向量"和"compconf"；`besdktest` 的随机身份；每个消费者一条乱序属性测试 |
| `07-registries.md` | 去掉 `_archive`；加 `resource-types.tsv`、`data-subjects.tsv` 和 bucket 列；`permissions.tsv` 追加 `delegable` 列，登记表的列只许追加，一行只写到它最后一个非空列；`PG_SCHEMA` 不超过 40 个字符（P10.1） |
| `01-development-workflow.md` | 发版走 `brickkit release`，compconf 经 `component.yaml` 的 `release.checks` 接在上面（P20.5，brickKit ≥ v1.4.0），失败时拒绝打 tag，`--skip-checks` 会被打印出来；版本规则加上协议版本 |
| `05-data.md` | 两个法人；UUID 种子 |
| 根 `AGENTS.md` 的 Pitfalls | **加**：手写 `besdk_*` 表的 SQL；事务里发网络调用；模块里自己写 ticker；跨请求缓存 `Can`；SQL 里用 `CURRENT_DATE`；主键用 `BIGSERIAL`；金额用 `(18,2)` 或浮点；读没声明的配置键；列表漏了 acl 分支（List/Can 不一致）；按掩码字段排序；把事件 payload 原样展示给人；交易单据缺法人。**改**："`SET ROLE` 漏写 LOCAL"、"`os.Getenv`"、"`gin.New()`"这几行改成"绕过 SDK 的入口"一类说法。**删**：`SystemClient` 那一行（API 已不存在） |

### 7.7 任务清单（带依赖，按 lane 划分）

| ID | 任务 | lane | 依赖 | 产出 |
|---|---|---|---|---|
| R1 | 最小复现（§7.9），每条一个独立目录 | 各 lane 的第一步 | — | **已完成**：`dev/phase-06/repros/r1-01…r1-10`（含补测 r1-03b、r1-04b），汇总在 `dev/phase-06/repros/README.md` |
| S1 | be-protocol rc.1：P1–P20 中英文、schemas、参考 DDL | Spec | 用户已同意新建仓库（答复 P1） | tag `v1.0.0-rc.1` |
| S4 | rc.2：按阶段 B 第一波审查裁决改 be-protocol（正文、schemas、DDL、向量）和两个族契约，本文与 apis 文件同步 | Spec | G1–G3、P1–P3、T1–T3、A1–A2、O1 的报告 | tag be-protocol `v1.0.0-rc.2`、contract-infra-authz `v2.0.0-rc.2`、contract-infra-iam `v1.0.0-rc.2`；三门 SDK 重跑向量 |
| S2 | 第一批向量：authz core、money、幂等指纹、信封派生、日历、编号、错误映射、配置解析 | Spec | S1、K1 | `vectors/` |
| S3 | widget 契约：openapi、proto、events、errors.yaml、lifecycle.yaml、assembly.yaml、fixtures.yaml，以及行为说明 | Spec | S1 | `fixtures/widget/` |
| K1 | contract-infra-authz v2.0 | Authz 契约 | authz-architecture | 契约仓库 |
| K2 | contract-infra-iam v1.0 | IAM 契约 | foundations-data-platform §11.3 | 契约仓库 |
| G1–G11 | be-sdk-go：运行时 / 配置 / HTTP / 错误 / 鉴权 / 可观测（G1）→ Store / pgdialect / 平台迁移（G2）→ 事件（G3）→ 幂等（G4）→ Jobs / Reconciler（G5）→ Access / 投影 / 资源契约（G6）→ 生命周期 P0（G7）→ 日历 / money / ID / 编号 / 搜索 / blob / 缓存 / 快照（G8）→ besdktest（G9）→ 外壳启动器（G10）→ widget 和坏变体（G11） | Go | S1–S3、K1 | `v0.6.0-rc.N` |
| P1–P11 | be-sdk-python，同上 | Python | 同上 | 同上 |
| T1–T11 | be-sdk-ts，同上；数据库、迁移、事件是从零写 | TS | 同上 | 同上 |
| A1–A9 | be-acceptance：compconf 骨架与四个假服务（A1）→ core / obs / err / auth（A2）→ scope / grpc / outbound（A3）→ events / idem / db / jobs / lifecycle / blob（A4）→ shell（A5）→ 套件自检（A6）→ 新门禁先警告（A7，§7.3）→ authzconf core、busconf、lifecycleconf 的向量与黑盒（A8）→ versionbump 支持 `/v3` 和 SDK 版本（A9） | Acceptance | S1–S3；A3 及以后依赖 G11 / P11 / T11 里至少一个 | be-acceptance 0.5.0 |
| O1 | be-ops：authzgen（三门语言）；`resources`（含 `view_key`）/ `requires_capabilities` / `field` / `delegable` 的校验；`resource-types.tsv`、`data-subjects.tsv`；不再建 `_archive`；每个组件建**属主角色和运行角色**两个 LOGIN 角色、schema 归属主、默认权限给运行角色 DML（F27）；外壳角色 `GRANT <成员运行角色> … WITH INHERIT FALSE, SET TRUE`（PG16）；角色级超时；资源契约 openapi 的合并。**随 brickKit v1.2–v1.3 加三项生成**（bk5、bk7、bk11）：①每个组件 `configSchema` 的协议键段（按 `config-keys.yaml` 和 profile，含 `secret` / `mount: file`）；②`component.yaml` 的 `events:` 段（事件契约 + `fixtures.yaml` 的 `events.consumes`）；③边缘：从 `edge_routes` 写部署条目的 `paths`（K8s）和 Traefik 路由 `labels`（Docker / Podman，以路径段为界，外壳成员同时写到外壳条目上）、`infra/traefik/dynamic/edge.yml` 的 `be-edge` 中间件链、K8s 的共享 `ingressAnnotations`。三项各配一个门禁（`protocol-config-scan`、`events-declaration-scan`、`edge-routes-fresh`，§7.3），生成器先在 widget 和一个 pilot 组件上见红再见绿 | Ops | K1；S1（`config-keys.yaml`、P12.16） | be-ops 0.3.0 |
| D1–D4 | 决策（D1）、约定（D2）、foundations 的 `02-languages-and-component-protocol.md`（D3）、根 AGENTS（D4），中英两份 | Docs | 和 S1 并行；定稿依赖 C 阶段 | — |
| M1–M2 | 新建 mdm/org（M1）、mdm/currency（M2），两条并行（答复 P2） | 组件 lane ×2 | G、P、A2–A4、O1 | 3.0.0（`brickkit release` 经 `release.checks` 跑过 compconf） |
| X1–X4 | pilot：authz → iam → customer、print（后两个并行；customer 的额度带币种，依赖 M2） | 组件 lane | G、P、A2–A4、O1；customer 另依赖 M2 | 3.0.0（同上） |
| F1 | 冻结：修完 pilot 发现的问题；SDK v0.6.0；be-protocol v1.0.0 | 控制者 | X1–X4、M1–M2 | tag |
| W1 | 第一批：mdm/product、infra/workflow、infra/notification、integration/im-dingtalk | 组件 lane ×4 | F1 | 3.0.0 |
| W2 | 第二批：erp/inventory、erp/finance | ×2 | W1（product、workflow） | 3.0.0 |
| W3 | 第三批：erp/sales、crm/opportunity | ×2 | W2 | 3.0.0 |
| W4 | infra/bff-mobile | TS | W3（它钉的版本） | 3.0.0 |
| E1 | 门禁全部切成报错；`registry/permissions.tsv` 追加 `delegable` 列；项目配置定稿：`config/vars.yaml` 的族地址全部是 `$endpoint:` 引用（`AUTHZ_URL`、`AUTHZ_GRPC_URL`、`IAM_URL`、`IAM_GRPC_URL`），密钥值经 `_FILE` 键挂成文件，部署文件顶层 `network:`、基础资源 compose 把它声明成 `external`、Traefik 接在上面（Docker 29 上要 ≥ 3.6，compose 里钉 `traefik:v3.6`）；平台下限 brickKit ≥ v1.4.0（`release.checks`）；`brickkit lint --all` 和 `brickkit graph` 里能看到 `$endpoint` 边和事件边 | 控制者 | W1–W4 | — |
| H1–H4 | 外壳 T21–T24：go-core、go-infra、go-backoffice、py-render，1.1.0 | 外壳 lane ×4 | E1 | 1.1.0（外壳同样声明 `release.checks`，`brickkit release` 跑 `shell` profile） |
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
4. be-ops 生成属主 / 运行两个角色和 NOINHERIT 的外壳授权（外壳所在的库要 PG16）；不再建 `_archive`。
5. `config/vars.yaml` 的族地址改成 `$endpoint:` 引用：`AUTHZ_URL`、`AUTHZ_GRPC_URL`、`IAM_URL`、`IAM_GRPC_URL`，加上 `IAM_ISSUER`、`TENANT_ID`（0107 第二次改写；外壳承载成员时 brickKit 自动指向外壳，外壳发版不用改任何地址）。
6. 门禁 `sdk-version-scan`、`compconf-record-scan`、`dependency-version-scan` 都已经是报错模式；外壳和它的成员都在 `component.yaml` 里声明了 `release.checks`（P20.5），所以外壳发版时 `brickkit release` 就会跑 `shell` profile。

**不必**在外壳之前做的（P1 及以后）：

- 事件总线的 pgqueue 适配器（F10 要建，但不阻塞外壳）；
- 冷层适配器；
- 共享（`sharing`）、字段掩码在前端的端到端；
- authz-static、authz-openfga；
- iam-keycloak；
- 搜索帮手的 bigm 策略。

这些都在 P0 时把契约形状定好，之后只开能力、只加适配器。

### 7.9 风险与先做的最小复现（R1）

全部做完（2026-10-02）。每条的过程、原始输出和建议在各自目录的 README 里；汇总表在 [`../repros/README.md`](../repros/README.md)。下表"结果"一列只写结论和落到了本文哪里。

| # | 要验证的假设 | 为什么要先验证 | 结果 |
|---|---|---|---|
| 1 | Go：每个成员一个 `TracerProvider` 共用一个 `BatchSpanProcessor` 的导出器；otelgrpc 的 stats handler 用的是成员自己的 provider，不是全局的 | 外壳的核心不变量；otelgrpc 默认读全局 provider | **部分成立**（[r1-01](../repros/r1-01/README.md)）：朴素共享导出器 / BSP 会静默丢 span；otelgrpc 不给选项就读全局。→ P18.1、P19.3（导出器只由平台关闭，成员 BSP + 空 `Shutdown` 壳）、CP-SHELL-09/10 |
| 2 | grpc-go：按 proto 方法选项生成的 `WithDefaultServiceConfig`（retryPolicy + retryThrottling）真的生效；`MaxConnectionAge` 触发 GOAWAY 后客户端透明重连 | P7.5、P7.8 | **成立**（[r1-02](../repros/r1-02/README.md)），另三处细节：`maxAttempts` 含首发、定为 3；预算按 ClientConn、resolver 更新时回满；`≤ 10 %` 是稳态值。→ P7.8、P9 |
| 3 | grpc-js：同样的两点 | 选 grpc-js 的前提 | **大部分成立**（[r1-03](../repros/r1-03/README.md)）：重试和 GOAWAY 透明重连成立；预算按（进程，目标）共享且不回满；服务端没有 `MinTime` 强制。→ P7.5、P7.8、§5.3 的 ts-proto 选项 |
| 3b | （补测）ts-proto 和 Python protobuf 运行时能否读到 `(be.v1.max_items)` | P7.10 在 TS / Python 上的前提 | **成立**（[r1-03b](../repros/r1-03b/README.md)）：TS 读 `protoMetadata.options`，要加 `enumsAsLiterals=true`；Python 读 `GetOptions().Extensions`，besdk 附带 `be.v1.limits_pb2`；Go 未测。→ P7.10、§5.3 |
| 4 | asyncpg 和 pg：`SET LOCAL ROLE` / `search_path` 之后，预编译语句缓存不会跨 schema 串用（DB-6） | P10.2 在外壳里的正确性 | **成立，但缓存不能无条件开**（[r1-04](../repros/r1-04/README.md)）：不串数据，形状不同时确定性报 `0A000` / `42804`；`/* be:<schema> */` 前缀消除报错且保留缓存；连接归还干净。→ P10.2、P10.7 |
| 4b | （补测）pgx v5 同样的问题 | Go SDK 的 P10.2 | **成立**（[r1-04b](../repros/r1-04b/README.md)）：默认模式与 asyncpg 同样报错；`CacheDescribe` 修不好（`08P01`、`42804`），DB-6 的这条建议撤回；前缀修好且最快。→ P10.2 |
| 5 | PG16：`GRANT m TO shell WITH INHERIT FALSE, SET TRUE` 之后，`SET LOCAL ROLE m` 可用，而外壳角色对成员的表没有权限 | P19.5 | **成立**（[r1-05](../repros/r1-05/README.md)），另三点：成员之间的隔离靠 SDK 不靠库；CP-DB-03 要按 `application_name` 数；语法要 PG16。→ P10.2、P10.5、P10.7、P19.5（外壳要 PG16） |
| 6 | golang-migrate（iofs）、yoyo、node-pg-migrate 都会忽略 `migrations/lifecycle.yaml`，并且状态表都能放进组件自己的 schema | data-layer §6 第 1 步已经点名的问题 | **部分成立**（[r1-06](../repros/r1-06/README.md)）：node-pg-migrate 不忽略、默认锁是全库常量；三者都用会话级状态。→ P11.1（迁移连接例外、按 schema 的锁）、P11.3（状态表名单）、P11.11、apis §4 的 `migrate` 选项 |
| 7 | nats.go、nats-py、nats.js 的 JetStream pull consumer：durable 命名、`DeliverAll`、`BackOff` 与 `MaxDeliver` 的配合、`InProgress` | P12.5–P12.9 | **第 4 条不成立**（[r1-07](../repros/r1-07/README.md)）：BackOff 改写 AckWait、`Nak()` 不看 BackOff、InProgress 挡不住，同一事件会并发执行两次；nats-py 的 `add_consumer` 会改掉已有 durable。→ P12.5、P12.7、P12.9、P12.12（服务端不设 BackOff、MaxDeliver −1，SDK 负责延迟和 DLQ；最后一次允许的投递失败照常 Nak，下一次收到时进 DLQ），P2 的 `EVENTS_*` |
| 8 | Fastify：同一个进程里起多个实例、各自监听一个端口、各自一套钩子 | TS 外壳启动器 | **成立**（[r1-08](../repros/r1-08/README.md)），另两个细节：`connectionsCheckingInterval` 要设 1 s；`handlerTimeout` 答 503，要改成 504，错误处理器里 ALS 为空。→ P3.5、§5.3、apis §4 |
| 9 | Casdoor：access token 的 `aud`；discovery 加 PKCE 能不能在浏览器端完成 | iam 3.0.0 和前端 | **成立**（[r1-09](../repros/r1-09/README.md)）：PKCE 在浏览器端走得通；Casdoor 的 token `aud` 是 client_id，平台按 P5.3 天然拒收；默认 `tokenFormat: JWT` 把整条用户记录放进 token（安全问题，裁决 ag）。→ §7.5 iam-casdoor、contract-infra-iam |
| 10 | Python 3.14：asyncpg、grpcio、pyarrow 的 wheel 是否齐全 | 决定 Python 的运行时版本 | **成立**（[r1-10](../repros/r1-10/README.md)），但 asyncpg 要 0.31.0。→ §5.3（CPython 3.14、`asyncpg==0.31.0`、yoyo + `psycopg[binary]==3.3.6`、标准库 `uuid7`、pyarrow 只在 `besdk[cold]`） |

最小复现失败时，在 lane 里改设计，并在报告里写明，不在真实仓库上硬铺开（记忆："没验证过的机制先写最小复现"）。

---

## 8. brickKit 可以支持或推荐的（候选，交给 lane E 处理）

> **结论（2026-10-03，brickKit v1.2.0–v1.3.1 的答复，`brickkit-feedback/replies/phase-06.md`）**：B1 不做（FR06-014），改为 O1 生成；B2 做了 `protocol` → `appProtocol`，headless 伴生 Service 不做（FR06-008）；B3（FR06-006 `readinessCheck`）、B4（FR06-009 `stopGracePeriodSeconds`）、B8（FR06-012 `mount: file`）、B10（FR06-001，做成 `$endpoint:` 而不是 `dependencies.slots`）、B11（FR06-005 `events:`）已落地并写进本文 P1、P2、P12；B5（FR06-029）、B7（FR06-013，改由组件声明 `PG_MIGRATION_HOST` 这类键）、B12（FR06-020，契约迁移门禁改由运行时靠会话 `application_name` 自己做，P11.4）不做；B14（FR06-028）在 brickKit v1.4.0 落地为 `release.checks`（P20.5、§4.6）；另有 FR06-007（定时任务）不做，0508 不变。
>
> 按记忆里的规则，下面全部是**候选**："不支持"的判断来自 `brickkit docs`（v1.1.0）和源码仓库 `docs/en/` 的检索，还没有在重建后真机复现。lane E 先把它们放进 `dev/phase-06/to-verify.md`；分成"问题"（必须验证）和"功能请求"（问能不能支持）两类。和前文重复的只列编号，不再展开。

| # | 候选 | 依据 | 对所有用户的好处 |
|---|---|---|---|
| B1 | （→ FR06-014）**configSchema 片段复用**：configSchema 可以引用一个版本化的外部片段，例如 `$ref: be-protocol@1.0#/config/db`，由 `brickkit lint` 展开校验 | 协议级配置键大约 25 个，要在 13 个组件里各抄一遍；docs 里找不到 `$ref` 或片段机制（data-lifecycle-v2 §8 第 3 条也提过） | 任何"一组组件共用同一套运行时约定"的项目，都不用手抄配置 schema |
| B2 | （→ FR06-008）`extraPorts[].protocol` + 可选的 headless 伴生 Service | foundations-communication §12 F1 | — |
| B3 | （→ FR06-006）**readiness 和 liveness 分开配路径**：component.yaml 可选 `readinessCheck.path`。K8s 的 readinessProbe 打它，compose 可以忽略 | 生成器今天让 startup、readiness、liveness 三个探针都打健康检查路径（`06-architecture/04-deploy-file-generation`）；协议的 `/readyz` 没地方接（P1.4） | 滚动更新时不把流量给还没拿到 bundle 的实例，又不违反"健康检查只查自己" |
| B4 | （→ FR06-009）优雅停机时长 `deployment.stopGracePeriodSeconds` | docs 里找不到 stopGrace / terminationGrace；P1.6 需要平台的宽限期大于 `SHUTDOWN_GRACE` | — |
| B5 | （→ FR06-029（新））**组件的语言声明**，例如可选的 `runtime.language`：`brickkit status` / `graph` 里显示；`lint` 检查外壳成员的语言和外壳一致 | 今天只有给 `mode: local` 用的 `local.language`。外壳一个进程只能装一门语言，这条约束 brickKit 看不见 | 多语言项目在组装期就能发现"把 Python 成员塞进 Go 外壳" |
| B6 | （→ brickKit v1.1.0 已支持（OCI label `io.brickkit.shell.members` + `IMAGE_STALE`）；go.mod 那一半仍是本项目的门禁；见 to-verify V-17）**外壳镜像自报成员版本**：`brickkit build` 给外壳镜像打 OCI label `io.brickkit.shell.members`；`up` 时和 `shell.members` 比对 | 根 AGENTS 易错点："go.mod 与 shell.members 不一致 → 镜像跑的是别的代码，没有任何报错" | 把一个静默的坑变成组装期的错误 |
| B7 | （→ FR06-013）迁移容器可以单独覆盖少量环境变量（`PG_MIGRATION_HOST`，以及**只给迁移容器**的 `PG_OWNER_USER` / `PG_OWNER_PASSWORD`） | foundations-data-platform §15 第 2 条。具体动机（裁决 p）：F27 把属主角色和运行角色分开，让运行期的 SQL（注入、AI 写出的语句）不能 DROP / ALTER；但 brickKit 给迁移容器的环境与服务相同（`05-migration/02`），运行进程于是也收到属主口令，这道防线只剩"SDK 自觉不用"。能单独给迁移容器变量，属主口令就不进运行进程 | 任何"迁移要比服务更高权限"的项目都能做到最小权限 |
| B8 | （→ FR06-012）密钥以文件挂载的形式交付 | 同上，第 3 条 | — |
| B9 | （→ FR06-002 / FR06-003）**09-patterns 增加一页"多语言组件：协议 + 黑盒一致性套件"**，以及"族契约仓库 + 一致性套件"（同 foundations-communication §12 F8、data-lifecycle-v2 §8 第 6 条） | 本项目是它的实例：规范、向量和夹具放在契约仓库；每门语言一个参考实现；对容器做黑盒测试（本项目里组件协议套件的路径是 `tools/be-acceptance/conformance/component/`，C1） | 给 AI 一个可以照做的"可替换、可换语言"的验收方式 |
| B10 | （→ FR06-001）按槽位声明依赖（`dependencies.slots`） | foundations-data-platform §15 第 1 条 | — |
| B11 | （→ FR06-005）事件的发布和订阅声明，只用于 `graph` / `status` 展示 | foundations-communication §12 F7 | — |
| B12 | （→ FR06-020）把"并存的版本"暴露给迁移进程 | foundations-data-platform §15 第 4 条 | — |
| B13 | （→ 不提：brickKit 有意只校验键名（`11-reference/04-config-schema-spec`））`lint` 和 `up` 按 configSchema 的 `type` 校验字面值 | 同上，第 7 条；协议 P2.3 在运行期做了同样的事 | 错误提前到组装期 |
| B14 | （→ FR06-028，brickKit v1.4.0 已落地：`release: {checks: [[make, conformance]]}`，失败报 `RELEASE_CHECK_FAILED`，见 P20.5、§4.6）**发版前钩子**，例如 `release.checks: [make conformance]`：`brickkit release` 跑完之后才打 tag | 发版流程（§4.6）要求"先有 compconf（`tools/be-acceptance/conformance/component/`）报告，再打 tag"，今天只能靠技能文档约束；先要核实 `brickkit release` 有没有类似的钩子 | 任何项目都能把自己的验收挂到发版上 |

---

## 9. 要用户拍板的点

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| ★Q1 | **新建 GitHub 仓库 `brickKit/be-protocol`**，放规范、schema、向量和夹具契约 | **已答复（P1）：建**，与三个 SDK 平级、单独发版（v1.0.0 起），建仓库那一刻先告诉用户。原推荐理由：规范不属于任何一门语言，而且必须和向量同一个版本号（§3.1） | 先放在 `tools/be-acceptance/protocol/`，目录结构不变，以后再搬出去。代价是规范的版本和套件的版本绑在了一起 |
| ★Q2（已定 P3：同意） | **同一门语言出现第二个组件之前，必须先锁栈**（给 0103 加一行），并决定要不要做官方 SDK | 同意。不锁栈，同一门语言里就会有两套写法，而且永远进不了外壳 | 允许一门语言内多套栈，只能单独运行，靠 compconf 守住 |
| Q3 | **法人和汇率的主数据什么时候建**：`mdm/org`（法人、时区、会计年度起始月）、`mdm/currency`（F4） | **已答复（P2）：这一轮就建**，排在其余组件升 3.0.0 之前（§7.2 阶段 C 的 M1、M2）；不设 `LEGAL_ENTITIES`，汇率不限定为 1。以下是原推荐，已被否决：不放进这一轮。法人先用共享变量 `LEGAL_ENTITIES` 过渡（P11.9）；币种列和汇率列这一轮都建好，但汇率限定为 1（只允许本位币单据），等 `mdm/currency` 建成再放开。两个组件排在外壳之后，作为 P1 的第一批新组件 | 现在就建两个新组件，放进 D 阶段第一批。代价是多两个组件；finance 和 sales 要多等一批 |

---

## 附录 A：平台表参考 DDL（设计稿；定稿在 be-protocol `ddl/`，两者不一致时以 `ddl/` 为准）

所有表都在组件自己的 schema 里，由 SDK 的平台迁移在迁移步骤里以**属主** `PG_OWNER_USER` 建，所以属主是 `PG_OWNER_USER`；运行角色 `PG_USER` 经 schema 的默认权限得到 DML（由项目的数据库初始化设定，DDL 里不写 GRANT）（F27，裁决 p）。运行期需要的 DDL 只经属主建的 `SECURITY DEFINER` 函数（`ddl/10-lifecycle-functions.sql`，P10.12）。生命周期的五张表见 data-lifecycle-v2 §4.14，表名照用，不在这里重复（定稿在 `ddl/09-lifecycle.sql`）。

```sql
CREATE TABLE IF NOT EXISTS besdk_platform_version (component TEXT PRIMARY KEY, version INT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());

-- 事件发件箱：按 created_at 每周一个分区，分区名 besdk_outbox_<ISO 周年>w<WW>（如 besdk_outbox_2026w40，UTC 左闭右开，P16.6），由生命周期引擎维护（platform 类，全部 PUBLISHED 之后保留 14 天）
CREATE TABLE IF NOT EXISTS besdk_outbox (
  id                 UUID        NOT NULL,             -- UUIDv7 = ce-id = Nats-Msg-Id
  created_at         TIMESTAMPTZ NOT NULL,             -- = IDTime(id)
  subject            TEXT        NOT NULL,
  aggregate_type     TEXT        NOT NULL,
  aggregate_id       TEXT        NOT NULL,
  aggregate_version  BIGINT      NOT NULL,
  occurred_at        TIMESTAMPTZ NOT NULL,
  traceparent        TEXT        NOT NULL DEFAULT '',
  tracestate         TEXT        NOT NULL DEFAULT '',  -- 非空时随信封发出（rc.2）
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

-- Jobs（保留：job_slot 30 天，job_queue 里 done 的行 7 天，P14.7）
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

-- 授权投影（ddl/07：只在 assembly.yaml 声明了 resources 的组件里建，CP-DB-04）
CREATE TABLE IF NOT EXISTS besdk_authz_acl (rtype TEXT NOT NULL, rid TEXT NOT NULL, relation TEXT NOT NULL, subject TEXT NOT NULL,
  expires_at TIMESTAMPTZ, revision BIGINT NOT NULL, PRIMARY KEY (rtype, rid, relation, subject));
CREATE INDEX IF NOT EXISTS besdk_authz_acl_subject ON besdk_authz_acl (rtype, subject, relation);
CREATE TABLE IF NOT EXISTS besdk_authz_cursor (scope TEXT PRIMARY KEY, revision BIGINT NOT NULL, rebuilt_at TIMESTAMPTZ);

-- 单据编号
CREATE TABLE IF NOT EXISTS besdk_number_series (series TEXT NOT NULL, scope TEXT NOT NULL DEFAULT '', period TEXT NOT NULL DEFAULT '',
  next_value BIGINT NOT NULL DEFAULT 1, gapless BOOLEAN NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (series, scope, period));
-- 编号唯一性：不分区的分配表，和单据同一个事务插入（P11.10，S-b 裁决 ao）；分区单据表上的唯一索引管不住跨分区重号
CREATE TABLE IF NOT EXISTS besdk_number_allocations (legal_entity_id TEXT NOT NULL, series TEXT NOT NULL, number TEXT NOT NULL,
  allocated_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (legal_entity_id, series, number));

-- 可续跑的回填（foundations-data-platform §6.4）
CREATE TABLE IF NOT EXISTS besdk_backfill (name TEXT PRIMARY KEY, cursor TEXT NOT NULL DEFAULT '', done BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
```
