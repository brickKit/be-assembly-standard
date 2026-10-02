[English](../../en/04-foundations/README.md) · [中文](README.md)

# 底层选择

组件下面的每一块为什么是现在这样：数据库、标识、时间与金额、事务、事件、调用、后台任务、身份、授权、可观测性、配置、外壳。每个关键选择一篇。每篇说明我们选了什么、让它可以替换的契约是什么、还有哪些实现、什么情况下会换、换的时候具体动哪些东西。读者是要改 SDK、外壳、`infra/`、`tools/be-ops` 或 `tools/be-acceptance` 的人，以及提议替换其中某一块的人。

## 阅读顺序

| 你在做什么 | 读什么 |
|---|---|
| 写或改一个组件 | [约定](../01-conventions/README.md)。约定说明每一块怎么用；只有约定链到某篇底层文档，或者你想知道为什么时，才打开它 |
| 改官方 SDK、外壳、`infra/` 里的基础资源、`be-ops` 或 `be-acceptance` | 先读本 README，再读你要改的那一块的文档，再读它列出的决策 |
| 提议"把 X 换掉"、"加一个缓存 / 队列 / 引擎"、"支持数据库 Y" | 先看下面的[端口表](#端口)，再看那个端口的文档：它的**什么时候换**和**怎么换**两节会告诉你，这个请求是改一个配置值、加一个适配器、加一个槽位族成员，还是不在范围内 |
| 用 Go、Python、TypeScript 以外的语言写组件 | 先读 [02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)，再读约定 |

决策优先于底层文档：两者不一致时，在决策被修改之前以决策为准（[决策索引](../02-decisions/README.md)）。

## 本目录与其他目录的分工

同一个主题出现在三个地方，各自回答不同的问题，没有一处重复。

| 目录 | 写什么 | 不写什么 |
|---|---|---|
| [`02-decisions/`](../02-decisions/README.md) | 一句话结论、两三句理由、挡下什么、何时重新讨论；并链到底层文档里有完整分析的那一节 | 方案对比、端口契约、测试清单 |
| `04-foundations/`（本目录） | 我们的选择、端口契约、备选方案、为什么选它、为什么不选其他、什么时候换、怎么换、一致性测试；**相关决策**一节链到它所支撑的决策 | "挡下什么"清单（改为链到决策）、怎么调用某个 API 的编码规则（改为链到约定） |
| [`01-conventions/`](../01-conventions/README.md) | 怎么用：用哪个 API、怎么写、要避开的错误 | 为什么这样选（改为链到这里） |

## 十一个小节

除本 README 之外，每篇底层文档都恰好有下面这些 `##` 小节，顺序固定，中英两版相同。形状固定，AI 能直接跳到需要的部分，`make docs-mirror` 也能校验两版是否成对。

| 序号 | 英文标题 | 中文标题 | 写什么 |
|---|---|---|---|
| 1 | Scope | 范围 | 这篇文档回答什么问题，哪些内容留给哪篇别的文档 |
| 2 | Choice | 选择 | 我们用什么，几行说清楚；后面跟一行**状态**：已在用、已定（随 3.0.0 组件统一升级落地）、以后再做 |
| 3 | Port contract | 端口契约 | 线协议、数据库或协议层面的契约：配置键、URL scheme、表结构、请求头、消息字段、状态码、错误 reason。绝不写成某一门语言的 API：组件可以用任何语言写 |
| 4 | Alternatives | 备选方案 | 主流方案，如实写出长处与短处 |
| 5 | Why this choice | 为什么选它 | 决定了这个选择的理由 |
| 6 | Why not the others | 为什么不选其他 | 每个备选方案具体缺了什么、会坏什么 |
| 7 | When to switch | 什么时候换 | 能观察到的、足以支持更换的触发条件 |
| 8 | How to switch | 怎么换 | 换的时候具体动哪些东西：一个配置值、一个版本钉、一个适配器、一个槽位族成员。绝不是"重写逻辑" |
| 9 | Conformance tests | 一致性测试 | 每个实现都必须通过的测试套件，以及要先写红的测试 |
| 10 | Decision records | 相关决策 | 本文支撑的决策（带链接），以及计划新增或修订的决策（纯文本，文件存在之前不加链接） |
| 11 | Known limits | 已知限制 | 这个选择做不到的事，直说；只有一个适配器的端口也在这里写明 |

## 状态用语

| 用语 | 含义 |
|---|---|
| **已在用** | 已发布的组件和 SDK 今天就是这样运行的 |
| **已定** | 设计已经定下；代码随 3.0.0 组件统一升级及与之配套的 SDK 版本落地 |
| **以后再做** | 已经命名，设计到足以让契约留好位置；等它的**什么时候换**一节里的触发条件出现时再建 |

## 文件

| 文件 | 回答什么 | 文档 |
|---|---|---|
| `README.md` | 本索引、端口表、小节形状 | 已写 |
| [01-ports-and-adapters.md](01-ports-and-adapters.md) | 什么算端口；适配器怎么选；一致性套件怎么组织；SDK 与协议的版本怎么演进；只有一个适配器的端口怎么如实标注 | 已写 |
| [02-languages-and-component-protocol.md](02-languages-and-component-protocol.md) | 每个组件自由选语言；语言中立的组件协议及其黑盒一致性套件；官方 SDK；一个外壳只合并同一种语言的成员 | 已写 |
| [03-database.md](03-database.md) | PostgreSQL 方言族、版本承诺、兼容发行版、schema 与角色隔离、按成员的连接池、连接池代理的规则、角色超时、高可用与备份的入口 | 已写 |
| [04-identifiers-and-numbering.md](04-identifiers-and-numbering.md) | UUIDv7 主键、引用存文本、从 id 派生的分区键、游标、单据编号（含无缺号的凭证号） | 已写 |
| [05-time-and-calendars.md](05-time-and-calendars.md) | 瞬时与业务日期、法人的业务时区、UTC 会话、事件里的业务日期、会计期间与会计年度 | 已写 |
| [06-money-quantity-units.md](06-money-quantity-units.md) | 金额、单价、汇率的列规格，币种成对，ISO 4217，舍入与分摊，跨语言向量，计量单位 | 已写 |
| [07-tenancy.md](07-tenancy.md) | 租户 = 部署、法人维度、`tenant_id` 与 `aud`、吵闹的邻居 | 已写 |
| [08-schema-evolution.md](08-schema-evolution.md) | 迁移工具与护栏、expand/contract、并存版本、回填、只前滚 | 已写 |
| [09-data-lifecycle.md](09-data-lifecycle.md) | 热、温、冷与销毁，法律保全，冷存储与冷查询适配器，分区窗口 | 已写 |
| [10-local-transactions.md](10-local-transactions.md) | 隔离级别、超时、重试、加锁顺序、advisory 锁、事务里不走网络 | 已写 |
| [11-consistency-across-components.md](11-consistency-across-components.md) | outbox 与 inbox、saga、对账器、挂起 | 已写 |
| [12-event-bus.md](12-event-bus.md) | 队列选型与 broker 端口：默认 JetStream，另有 PostgreSQL 队列适配器 | 已写 |
| [13-event-contracts.md](13-event-contracts.md) | 信封（CloudEvents）、命名、聚合流、schema 演进 | 已写 |
| [14-system-rpc.md](14-system-rpc.md) | 组件之间的 gRPC 系统面 | 已写 |
| [15-user-api-and-errors.md](15-user-api-and-errors.md) | REST 用户面与错误模型（AIP-193 映射、reason 登记表） | 已写 |
| [16-deadlines-and-retries.md](16-deadlines-and-retries.md) | 时间预算、重试预算、舱壁 | 已写 |
| [17-caching.md](17-caching.md) | 缓存，以及为什么没有 Redis | 已写 |
| [18-edge.md](18-edge.md) | 边缘与网关 | 已写 |
| [19-background-jobs.md](19-background-jobs.md) | 后台任务端口与调度 | 已写 |
| [20-authorization-provider.md](20-authorization-provider.md) | 授权 provider 契约、资源契约、槽位族及其一致性套件 | 已写 |
| [21-identity-provider.md](21-identity-provider.md) | IAM 槽位、token 形状、JWKS、平台自有的 `sub`、目录事件、Keycloak 成员 | 已写 |
| [22-object-storage.md](22-object-storage.md) | S3 端口、每组件一个 bucket、blob 客户端、附件、预签名 URL、冷存储 | 已写 |
| [23-observability.md](23-observability.md) | 传播、按成员的 resource、指标、日志字段、审计日志与应用日志 | 已写 |
| [24-config-and-secrets.md](24-config-and-secrets.md) | 环境变量配置面、brickKit 的几种值形式、密钥端口与轮换 | 已写 |
| [25-search.md](25-search.md) | 组件内的 `q` 帮手、全局搜索槽位族 | 已写 |
| [26-i18n-data.md](26-i18n-data.md) | 可翻译的主数据、标准代码、服务端语言 | 已写 |
| [27-shells.md](27-shells.md) | 合并安全：逐项核对表与四条外壳不变量 | 已写 |

## 端口

端口是基础设施边界上带一致性套件的契约，判据见 [01-ports-and-adapters.md](01-ports-and-adapters.md#选择)。套件放在 `tools/be-acceptance/conformance/<套件>/`。"单适配器端口"的意思是：它的价值在于一套统一的语义加一个套件，不在于能换。

| 端口 | 组件看到的东西（线协议层面） | 默认 | 其他实现 | 套件 | 状态 | 文档 |
|---|---|---|---|---|---|---|
| 组件协议 | 经环境变量拿配置、`/healthz`、验 token、事件信封、outbox 与 inbox 表、幂等、数据范围、日志与指标字段 | be-sdk-go、be-sdk-python、be-sdk-ts（官方实现） | 任何语言里通过套件的实现 | `component`（黑盒，对运行中的容器测） | 已定 | [02](02-languages-and-component-protocol.md) |
| 数据库引擎 | PostgreSQL 线协议加一份能力清单；`PG_*` 键 | PostgreSQL ≥ 14（外壳用 NOINHERIT 授权时要 16） | 托管 PostgreSQL；横向扩展用 Citus 12+；人大金仓、瀚高待实测 | `db` | PostgreSQL 已在用；套件已定 | [03](03-database.md) |
| Store 与本地事务 | 每个事务在事务内设定角色、`search_path` 与超时；遇到序列化失败和死锁自动重试 | SDK 的 PostgreSQL 方言层 | 无：跟着引擎走 | `store` | 已定 | [10](10-local-transactions.md) |
| 事件总线 | outbox 表、事件信封、总线地址的 scheme | NATS JetStream | PostgreSQL 队列（阶段 06 内建）；Kafka（以后再做） | `bus` | 已定（今天在用的是 NATS 核心） | [12](12-event-bus.md)、[13](13-event-contracts.md) |
| 后台任务 | 任务声明；组件自己 schema 里的租约表与时间槽表 | 原生 PostgreSQL 表 | 无，单适配器端口（River、DBOS 只作参考，不作适配器） | `jobs` | 已定 | [19](19-background-jobs.md) |
| 系统 RPC | 组件之间的 gRPC、身份 metadata、截止时间、带 reason 的 `google.rpc.Status` | 各官方 SDK 里的 gRPC，连接复用 | connect-go 服务端（与 gRPC 线协议兼容） | `rpc` | gRPC 已在用；连接复用与截止时间已定 | [14](14-system-rpc.md)、[16](16-deadlines-and-retries.md) |
| 用户 API | REST、每条路由一个权限键、带 reason 的 RFC 9457 problem details | 各语言锁定的 HTTP 栈 | 无，单适配器端口 | `userapi` | 已定 | [15](15-user-api-and-errors.md) |
| 缓存 | 线上没有任何东西：只在进程内 | 进程内 LRU 加 TTL | 无：没有缓存服务器 | `cache` | 已定 | [17](17-caching.md) |
| 边缘 | `assembly.yaml` 里的 `edge_routes`，由 be-ops 生成路由 | Traefik file provider | Kubernetes Ingress 或 Gateway API、nginx | `edge`（黄金路由表加端到端） | 已定 | [18](18-edge.md) |
| 可观测性 | OTLP、W3C `traceparent`、`service.name` = 成员的组件 ID | OTLP 发给 OpenTelemetry Collector | 任何 OTLP 后端，在 collector 里换 | `telemetry` | 导出已在用；传播已定 | [23](23-observability.md) |
| 对象存储 | `S3_URL` 上的 S3 API，每个组件一个 bucket、一份凭据 | RustFS | MinIO、AWS S3、阿里云 OSS | `blob` | 地址已在用；客户端已定 | [22](22-object-storage.md) |
| 冷存储 | 冻结数据在对象存储里的格式与清单 | `s3-parquet` | `none`（显式降级）；Iceberg（以后再做） | `lifecycle` | 已定 | [09](09-data-lifecycle.md) |
| 冷查询 | 把冻结的行读回来 | `none`（答一个声明过的"该范围已冷"错误） | `scan`（已定）；Trino（以后再做） | `lifecycle` | 已定 | [09](09-data-lifecycle.md) |
| 密钥来源 | 密钥值怎么读取、怎么重读，从而轮换不用重启 | 环境变量 | 挂载文件，变更后重读；OpenBao（以后再做） | `secret` | 环境变量已在用；文件已定 | [24](24-config-and-secrets.md) |
| 授权 provider（槽位族） | provider 契约、`AUTHZ_URL` 下的 bundle、每个组件都提供的资源契约端点 | `infra/authz` | `infra/authz-static`、`infra/authz-openfga`（都在阶段 06 内建）；Cedar 或 OPA（以后再做） | `authz` | `infra/authz` 已在用；族已定 | [20](20-authorization-provider.md) |
| 身份提供方（槽位族） | OIDC discovery、按 RFC 8693 形状的 token 交换、`IAM_JWKS_URL` 上的 JWKS、平台自有的 `sub`、目录事件 | `infra/iam-casdoor` | `infra/iam-keycloak`（第二个）；通用 OIDC + SCIM 成员（第三个） | `iam` | Casdoor 成员已在用；族已定 | [21](21-identity-provider.md) |
| 全局搜索（槽位族） | 由事件喂入、按调用者的访问权限过滤的投影 | 暂无 | `infra/search-*` 成员 | `search` | 以后再做 | [25](25-search.md) |

共享语义不是端口，没有套件：每个官方 SDK 读同一份 JSON 向量，必须算出相同的结果。全协议通用的向量放在 `brickKit/be-protocol` 仓库的 `vectors/` 里（[02](02-languages-and-component-protocol.md#be-protocol-的仓库结构)），旁边是协议正文、它的 schema 和平台表的参考 DDL。槽位族的向量放在族契约仓库里，以那里为准：授权决策在 `contract-infra-authz`（`contracts/infra/authz`）的 `vectors/decision/`，锁定它的 `EVALUATION.md`；token 在 `contract-infra-iam`（`contracts/infra/iam`）的 `vectors/tokens/`；be-protocol 按标签引用它们，从不复制。套件和 SDK 的单元测试都从固定的标签读取每一套。

| 向量 | 校验什么 | 文档 |
|---|---|---|
| `money` | 解析、格式化、舍入、分摊、税额行 | [06](06-money-quantity-units.md) |
| `calendar` | 瞬时加时区得出业务日期 | [05](05-time-and-calendars.md) |
| `numbering` | 编号格式与编号序列的范围 | [04](04-identifiers-and-numbering.md) |
| `errors` | problem 错误体、码的映射、日志级别、SQLSTATE 映射 | [15](15-user-api-and-errors.md) |
| `envelope` | 事件信封的头、名字、id、聚合游标 | [13](13-event-contracts.md) |
| `idempotency` | 幂等键的判定与请求指纹 | [11](11-consistency-across-components.md) |
| `config` | 配置键、取值形式、端点 | [24](24-config-and-secrets.md) |
| `redaction` | 日志里密钥与个人数据的脱敏 | [23](23-observability.md) |
| `search`（提议中，尚未编写） | `q` 的归一化：大小写折叠、全半角、拼音、首字母、转义、排序 | [25](25-search.md) |
| i18n 回退（提议中） | 在 `name_i18n` 上走的语言回退链 | [26](26-i18n-data.md) |
| `decision`（在 `contract-infra-authz`） | 由 bundle、token 和记录的事实得出授权决策 | [20](20-authorization-provider.md) |
| `tokens`（在 `contract-infra-iam`） | access token 与 subject token 的验证 | [21](21-identity-provider.md) |
