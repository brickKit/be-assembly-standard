[English](../../en/04-foundations/02-languages-and-component-protocol.md) · [中文](02-languages-and-component-protocol.md)

# 语言与组件协议

每个组件可以用任何编程语言写。本文说明：一个组件不论用什么语言，怎样才算本项目的合格成员——语言中立的组件协议、评判它的黑盒一致性套件、实现它的官方 SDK，以及两道彼此独立的关："能单独运行"和"能进外壳"。要改官方 SDK 或套件、要用 Go、Python、TypeScript 以外的语言写组件、要提议引入一门新语言之前，先读这篇。

## 范围

- **覆盖：** 每个组件自由选语言；组件协议：管什么、怎么版本化、放在哪；黑盒套件：对什么跑、组件怎么加入、报告与门禁；两道关；官方 SDK 以及各自锁定的栈；各语言的外壳启动器（在本文汇总）；第四门语言的接入路径。
- **不覆盖：** 协议各部分的细节。那些留在各自的底层文档里（[端口契约](#端口契约)下的表逐项指过去）。外壳不变量与合并安全核对表：[27-shells.md](27-shells.md)。所有端口共用的规则、SDK 版本怎么演进：[01-ports-and-adapters.md](01-ports-and-adapters.md)。用官方 SDK 写组件的写法：[02-backend.md](../01-conventions/02-backend.md)。

## 选择

- **每个组件自己选语言。** 组件必须遵守的规则不再住在某一门语言的 SDK 里，而是**组件协议**：在线协议格式、表结构、配置键这一层定义。
- **协议有自己的仓库** `brickKit/be-protocol`（https://github.com/brickKit/be-protocol）。里面是规范正文（英文为准、中文镜像）、JSON Schema、平台表的参考 DDL、语义向量和夹具组件的契约。唯一的代码是一个很小的 Go 模块，把这些文件嵌进去给测试用。它单独版本化，`MAJOR.MINOR`，先出候选版，再从 `v1.0.0` 起步。minor 版本只加可选的面。
- **是否符合，从外面判。** 套件 `tools/be-acceptance/conformance/component/`（非正式简称 compconf）对一个**运行中的容器**测：它的端口、它写的表、它发的消息、它的日志和指标。它从不读源码，所以 Go、Python、TypeScript 和第四门语言的组件用的是同一组用例。
- **官方 SDK 是参考实现。** `be-sdk-go`、`be-sdk-python`、`be-sdk-ts` 实现这份协议，三门语言用同一组名词。任何 SDK 都不许有规范没写的行为：先改规范。
- **两道关，分开把。** *能单独运行*：任何语言的组件，只要通过适用于它的套件 profile，就能进 `brickkit.yaml`。*能进外壳*：只有当这门语言有官方 SDK **并且**有该 SDK 的外壳启动器时才行，因为外壳是一个进程、一个运行时、一个 SDK 版本（[27-shells.md](27-shells.md)）。
- **每门语言锁一套栈。** 一门语言出现第二个组件之前，先在 [0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md) 里给它加一行栈，并决定要不要给它做官方 SDK。
- **允许 JVM 或 CLR 语言。** 它的内存和启动开销写进组件 `BRICKKIT.md` 的 "Before you deploy" 一节作为提醒，不再是禁令。

**状态**：已定。`be-protocol` 仓库已建，1.0 正文正在写（先出候选版）。SDK 经候选版走向 v0.6.0：pilot 组件之后 v0.6.0 冻结 API，外壳在真机上验证通过后，同一份代码打 v1.0.0。今天的 SDK（v0.5.0）把规则写在代码里，三门之间并不一致：TypeScript 没有数据库、事件和幂等。套件还不存在，所以还没有任何组件有一致性报告。

## 端口契约

### 协议覆盖什么

二十章，`P1`–`P20`。每条规则有一个等级。**MUST** 由套件测。**SHOULD** 只给警告。**INTERNAL** 是从外面看不见的规则（比如"事务里不发网络调用"）：官方 SDK 用自己的测试守住，第四门语言的组件在评审时核对。每条规则写明它对应的套件用例 `CP-<组>-<号>`。用例 ID 稳定，只增不改。

| 章 | 管什么 | 细节见 |
|---|---|---|
| P1 进程与生命周期 | 两个入口：默认命令起服务，`migration.command` 跑迁移；启动顺序（校验配置、开端口、再在后台连依赖）；配置非法以退出码 78 退出；`/healthz` 只答进程本身；`/readyz`（SHOULD）；SIGTERM 在 `SHUTDOWN_GRACE`（默认 20 s）内收尾；致命错误以非 0 退出；镜像里有 `/bin/sh` 和 `wget` | [27](27-shells.md)、[02-backend.md](../01-conventions/02-backend.md#健康检查与镜像) |
| P2 配置 | 只来自环境变量；只读组件在 `configSchema` 里声明过的键；类型严格；协议级键列在 `schemas/config-keys.yaml` | [24](24-config-and-secrets.md) |
| P3 HTTP 面 | 三类路径（用户面 API、运维端点、资源契约端点）；`X-Request-Id`；`traceparent`；按路由的截止时间；服务端超时；请求体上限 1 MiB；`Idempotency-Key`；游标分页 | [15](15-user-api-and-errors.md) |
| P4 错误 | RFC 9457 problem details，装着 AIP-193 的 `reason`、`domain`、`metadata`；reason 登记表 | [15](15-user-api-and-errors.md) |
| P5 身份 | JWT 验证，`iss`、`aud`、`typ` | [21](21-identity-provider.md) |
| P6 授权 | bundle、数据范围、资源契约、投影 | [20](20-authorization-provider.md) |
| P7–P9 调用 | gRPC 系统面、出站 HTTP、截止时间与重试预算 | [14](14-system-rpc.md)、[16](16-deadlines-and-retries.md) |
| P10 数据库 | 身份来自 `PG_OWNER_USER`（属主，只用于迁移）、`PG_USER`（运行期，只有 DML）和 `PG_SCHEMA`；每个事务 `SET LOCAL`，超时，连接池 | [03](03-database.md)、[10](10-local-transactions.md) |
| P11 迁移与数据形状 | 迁移护栏、expand/contract、UUIDv7 主键、金额精度、业务日期、`legal_entity_id`、编号 | [08](08-schema-evolution.md)、[04](04-identifiers-and-numbering.md)、[05](05-time-and-calendars.md)、[06](06-money-quantity-units.md)、[07](07-tenancy.md) |
| P12–P15 事件、幂等、后台工作、快照 | outbox、信封、游标、回放、命令幂等、Jobs、别人数据的本地副本 | [11](11-consistency-across-components.md)、[12](12-event-bus.md)、[13](13-event-contracts.md)、[19](19-background-jobs.md) |
| P16 数据生命周期 | `lifecycle.yaml`、`RANGE_COLD`、`/_lifecycle/*` | [09](09-data-lifecycle.md) |
| P17 对象存储 | 每个组件一个 bucket、一份凭据，预签名 URL | [22](22-object-storage.md) |
| P18 可观测性 | 日志字段、带 `be_` 前缀的指标名、传播 | [23](23-observability.md) |
| P19 外壳义务 | 一个外壳一门语言、一个 SDK 版本；进程级共享的四样东西；成员核对 | [27](27-shells.md) |
| P20 自描述 | `/_be/info`、协议版本 | 见下 |

### 自描述

主端口上的 `GET /_be/info`。它不经边缘路由、不鉴权、不含任何密钥：

```json
{
  "component_id": "erp/sales", "component_version": "3.0.0",
  "protocol": "1.0",
  "sdk": { "name": "be-sdk-go", "version": "0.6.0" },
  "language": { "name": "go", "version": "1.25.11" },
  "profiles": ["core", "auth", "scope", "grpc", "outbound", "events-pub", "events-sub", "idempotency", "db", "jobs", "lifecycle"],
  "ports": { "http": 8085, "grpc": 9095 },
  "migrations": { "component": "0001", "platform": 3 },
  "members": null
}
```

外壳上的 `members` 是同样形状的对象数组，每一项不带 `members`。组件在 `assembly.yaml` 里声明它按哪个协议版本受测；套件为每个协议 minor 各保留一套用例，所以旧组件永远按它声明的版本来测：

```yaml
protocol: "1.0"
language: rust                 # 只有没有官方 SDK 的语言才写
conformance:
  fixtures: conformance/fixtures.yaml
  skip:                        # 只能跳过可选用例，每条写理由
    - { case: CP-OUT-04, reason: "没有幂等的出站方法" }
```

### `be-protocol` 的仓库结构

| 路径 | 放什么 |
|---|---|
| `spec/NN-<领域>.md`（`00-reading-the-spec.md`、`01-process-and-lifecycle.md` … `20-self-description-and-versioning.md`），中文 `spec/NN-<领域>.zh.md` 放在各自旁边 | 规范正文，P1–P20 每章一个文件，外加一篇阅读指南，英文为准 |
| `schemas/` | `config-keys.yaml`、`errors-be.yaml`、`conformance-cases.yaml`，以及 problem 错误体、事件信封、事件契约、访问令牌声明、`lifecycle.yaml`、`DATA_LIFECYCLE`、`JOBS_OVERRIDES`、`errors.yaml`、`assembly.yaml` 里的协议键、`/_be/info`、`fixtures.yaml`、套件报告各自的 JSON Schema |
| `ddl/` | 每一张 `besdk_*` 表和平台函数的参考 DDL（`01-platform-version.sql` … `10-lifecycle-functions.sql`）；SDK 的平台迁移必须产出完全相同的表结构。`be_bus.sql` 是 PostgreSQL 总线适配器的 schema，由数据库初始化创建，不由组件创建 |
| `proto/`、`openapi/` | `be/v1/limits.proto`（`max_items`）、`be/lifecycle/v1/lifecycle.proto`；资源契约片段（`resource-authz.yaml`、`resource-lifecycle.yaml`）与运维端点（`ops.yaml`） |
| `vectors/` | 全协议共用的语义，写成 JSON 的输入输出对：金额、日历、编号、幂等、信封、错误、配置、脱敏；附 `SHA256SUMS`。`search` 一组还只是提案（[25](25-search.md)）。槽位族的决策向量不在这里：它们以族契约仓库为准（`contracts/infra/authz/vectors/decision/`），协议按 tag（`v2.0.0`）引用该族的 `EVALUATION.md` |
| `fixtures/widget/`、`fixtures/peer/` | 夹具组件及它所调用的假对端的契约与行为说明 |
| `fs.go`、`go.mod` | 唯一的代码：把上面这些文件嵌进去给 Go 使用方 |

`be-acceptance` 精确钉一个 `be-protocol` 版本。`be-sdk-go` 在测试里 import 它。`be-sdk-python` 和 `be-sdk-ts` 从某个 tag 拷贝 `vectors/` 和 `schemas/`，并核对 `SHA256SUMS`（族的决策向量同样从族契约的 tag 拷贝）：拷的是测试数据，不是代码（[0101](../02-decisions/01-architecture/0101-no-imports-between-components.md) 不受影响）。改动的顺序永远是：规范与 schema，然后向量，然后一条先对坏夹具跑出红的套件用例，然后三门 SDK，最后打 tag。

### 黑盒套件

- **真的基础设施：** `make up` 起的 PostgreSQL，库 `brickkit_test_db`，每次运行现建一个随机 schema、一个随机属主角色（`PG_OWNER_USER`，拥有表）、一个随机运行期角色（`PG_USER`，只有 DML，不是属主的成员）和一个以 `WITH INHERIT FALSE, SET TRUE` 获授运行期角色的外壳登录角色，跑完全部删掉；每次运行起一个一次性的 `nats-server -js`。
- **套件内的假服务：** 一个身份提供方（JWKS 加签发器，也签错 `iss`、错 `aud`、刷新令牌和 `HS256` 的令牌）、一个讲 `contract-infra-authz` v2 的授权提供方、每个依赖一个假对端（按依赖的 proto 描述符应答，记录 metadata、截止时间和连接数，可以挂起或报错），以及一个 OTLP 接收器。
- **配置：** 先取 `configSchema` 的默认值，盖上套件的值（随机库身份、假服务地址），再盖上任何运维都能调的调优键（`EVENTS_BACKOFF`、`EVENTS_MAX_DELIVER`、`GRPC_MAX_CONNECTION_AGE`、`JOBS_OVERRIDES`）。协议级配置键就是可测性接口：没有任何"测试模式"开关。
- **运行：** 先迁移两次，再起一个或两个副本；外壳则按 `BRICKKIT_SERVED_MEMBERS_CONFIG` 起。

profile 从清单自动选出，组件不用声明：

| profile | 什么时候启用 | profile | 什么时候启用 |
|---|---|---|---|
| `core`、`obs`、`err` | 一律 | `events-pub` | 它的事件契约里有它发布的 subject |
| `auth` | 有任何非公开路由 | `events-sub` | 订阅了任何 subject |
| `scope` | `data_scopes` 不是 `none`，或声明了资源 | `idempotency` | 任何写操作带幂等键 |
| `grpc` | 有名为 `grpc` 的 `extraPorts` | `db`、`jobs`、`lifecycle` | `configSchema` 里有 `PG_SCHEMA` |
| `outbound` | 有组件依赖 | `blob` | `configSchema` 里有 `S3_BUCKET` |
| `shell` | `component.yaml` 有 `shell.members`；每个成员的 profile 都按外壳形态重跑一遍 | | |

`conformance/fixtures.yaml` 告诉套件怎样让组件做事、怎样看到结果：测试用户及其授权，每种资源怎么建、读、列、发命令，每个依赖怎么应答，它产出和消费哪些事件，以及一条 `observe.sql`，用来读组件自己的表、观察没有公开读接口的效果。它是数据，不是代码，所以第四门语言的组件写的是同一份文件。

**报告与门禁。** 套件写出 `compconf-report.json`（schema 在 `be-protocol` 里）：套件版本、协议、组件与版本、镜像引用与摘要、SDK、基础设施版本、逐 profile 逐用例的结果、跳过的用例及理由。任何一条 MUST 失败，这次运行就失败。`make conformance ID=<组件> [SHELL=<外壳>]` 在本地跑。计划中的门禁 `compconf-record-scan` 进 `make gates`，离线运行：`brickkit.yaml` 里的每个组件和外壳，都要有对应精确版本的报告，报告里的镜像摘要等于本地镜像的摘要，套件版本不低于最低要求，必测 profile 全部通过。镜像重建了，就要新报告。

### 两道关

| | 能单独运行 | 能进外壳 |
|---|---|---|
| 谁 | 任何语言的组件 | 所用语言有官方 SDK 和外壳启动器的组件 |
| 需要 | 本版本的套件报告全绿；`assembly.yaml` 里写了 `protocol`；栈写进它的 `AGENTS.md` | 以上全部，并且与外壳的其他成员用同一个 SDK 版本构建；`shell` profile 全绿；外壳的成员核对（[27](27-shells.md)） |
| 扫源码的门禁（`bare-route-scan`、`identity-literal-scan`、import 检查） | 只对官方语言；其他语言由套件加上按 INTERNAL 清单的评审替代 | 全部适用 |
| `compconf-record-scan` | 适用 | 适用 |

### 官方 SDK

- **同一组名词。** 三门 SDK 对同一个概念用同一个名字，大小写按各语言惯例（PascalCase、snake_case、camelCase）。适配器（总线、数据库方言、冷存储）都在 SDK 内部，按 URL scheme 或配置值选用，组件从不 import 它们。
- **每门 SDK 自带夹具组件** `examples/widget`（`conformance/widget-go`、`-py`、`-ts`），定义只有一份，在 `be-protocol` 的 `fixtures/widget/` 里：每个生命周期类别一张表，一个带幂等命令和两段式命令的用户面 API，带条数上限的 gRPC 方法，发布和消费的事件，一个 cron 任务、一个 worker、一个对账器。每门 SDK 的 CI 都对它跑套件。同一个 widget 在三门语言里都过同一套用例，就是三门 SDK 等价的证据。
- **widget 的坏变体**用构建参数选，每个恰好违反一条规则：收刷新令牌、`/healthz` 查库、不带 `ce-id`、用裸 `SELECT` 认领 outbox、不切角色直接写、池没有上限、没有截止时间、泄露内部错误。
- 每门 SDK 在 `/_be/info` 和 README 里写明它实现的协议版本；`make vectors` 同步并跑向量，`make conformance` 构建 widget 并跑套件。

每门官方 SDK 锁定的栈（[0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md)，计划修订时加上 TypeScript 后端这一行）：

| 层 | Go | Python | TypeScript |
|---|---|---|---|
| 运行时 | Go 1.25 | CPython 3.14 | Node 24 LTS |
| HTTP | Gin | FastAPI on uvicorn，一个事件循环 | Fastify 5（BFF 的 GraphQL：graphql-yoga 5 挂在 Fastify 上） |
| gRPC | grpc-go | grpc.aio | @grpc/grpc-js，ts-proto 生成代码 |
| 数据库 | database/sql + pgx/v5、sqlc、手写 SQL | asyncpg 0.31.0、手写 SQL | pg（node-postgres）8、手写 SQL、zod 校验行 |
| 迁移 | golang-migrate | yoyo-migrations，配 psycopg[binary] 3.3.6 | node-pg-migrate |
| 事件 | nats.go JetStream | nats-py JetStream | @nats-io/jetstream |
| 十进制 | cockroachdb/apd v3 | `decimal` | decimal.js |
| JWT | golang-jwt v5 + keyfunc v3 | PyJWT（必须传 `audience`） | jose 6 |
| trace | otel-go | opentelemetry-python | @opentelemetry/sdk-trace-base，不用 auto-instrumentation |
| 时区数据（MUST 内嵌） | `time/tzdata` | `tzdata` 包 | full ICU |
| 测试 | testing + testify + rapid | pytest + hypothesis | vitest + fast-check |

Python：`pyarrow` 只放在 `besdk[cold]` 这个 extra 里；UUIDv7 用标准库（`uuid.uuid7`，3.14 新增）。每门 SDK 都内嵌自己的时区数据，所以业务日期从不依赖镜像里的 `/usr/share/zoneinfo`；时区数据一变，就重新交叉核对跨语言的日历向量（[05](05-time-and-calendars.md)）。

TypeScript 在 v0.6.0 补齐数据库、迁移、事件、幂等和 Jobs，所以它能承载任何组件，不再只能做 BFF。TypeScript 各项选择的理由见[为什么选它](#为什么选它)。

### 外壳启动器

每门官方 SDK 带着自己语言的启动器。它们实现的四条不变量和合并安全核对表见 [27-shells.md](27-shells.md)。

| 语言 | 成员版本从哪读 | 外壳仓库 |
|---|---|---|
| Go | Go 的 build info | `be/go-core`、`be/go-infra`、`be/go-backoffice` |
| Python | `importlib.metadata` | `be/py-render` |
| TypeScript | 成员包的 `package.json` | 暂时没有：唯一的 TypeScript 组件 BFF 永远不进外壳（[0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)）；启动器靠对两个 widget 实例跑 `shell` profile 证明可用 |

每门语言的语义相同：读 `BRICKKIT_SERVED_MEMBERS_CONFIG`；缺失、空串或 `null` 都是错误，`[]` 表示没有成员。列出的成员没有编译进来，或编译进来的版本不同，以 2 退出并点名该成员。某个成员的库地址、端口或库名、总线地址、授权地址、`IAM_*` 或 `TENANT_ID` 和外壳的不一样，以 78 退出。然后启动器只建一次进程级共享的四样东西，为每个成员建一个运行时，在成员自己的端口上服务它，用和单跑时同一个监督器监督全部后台工作，并在外壳自己的端口上提供 `/healthz` 和汇总的 `/metrics`。

### 第四门语言

1. **选一套栈**，写进组件 `AGENTS.md` 的 "Stack" 一节。在 `assembly.yaml` 里写 `protocol: "1.0"` 和 `language: <名字>`。
2. **按这个顺序实现**，每做完一步就多过一个 profile：`core`、`obs`、`err` → `auth` → `db`（身份、`SET LOCAL`、超时、池、按参考 DDL 的平台迁移）→ `events-pub`、`events-sub` → `idempotency`、`jobs`、`lifecycle` → `scope`、`grpc`、`outbound`。跑向量（SHOULD）；照着向量写，比读正文快。
3. **通过套件**：之后这个组件就能单独运行。
4. **按 INTERNAL 清单评审**：事务里不发网络调用；没有嵌套事务；每一次数据库访问都在事务里，并以 `SET LOCAL ROLE` 和 `search_path` 开头，没有会话级 `SET`；advisory 锁只用事务级的，键按协议的方式派生；列表 SQL 用求值出来的范围谓词，不用字符串拼出 `WHERE`；不跨请求缓存授权决策；原始 token 不进日志；只读声明过的配置键；全部后台工作都受监督；多行加锁按固定顺序。
5. **写明运行开销**：JVM 或 CLR 进程常驻 256–512 MiB，启动以秒计。调大 `healthCheck.startPeriodSeconds` 和 `requests.memory`，并写进 `BRICKKIT.md` 的 "Before you deploy"。brickKit 对语言没有要求：镜像、迁移容器、健康检查都与语言无关，`mode: local` 经 `local.runCommand` 能起任何裸进程。
6. **这门语言的第二个组件之前**：在 0103 加一行，决定要不要做官方 SDK。官方 SDK 的门槛：全部向量通过；它的 widget 通过 component、bus、lifecycle 三个套件；它的启动器通过 `shell` profile；带一个测试包；`02-backend.md` 里有它的一节。

## 备选方案

| | 长处 | 短处 |
|---|---|---|
| 锁死语言（即今天的 0105） | 规则只有一处；扫源码的门禁覆盖全部代码 | 组件用不上更好的生态；"可替换"止步于语言 |
| 协议加黑盒套件，SDK 作为参考实现（选定） | 任何语言；对所有组件同一个判定；套件同时是 SDK 的回归测试 | 要维护一份规范；官方语言以外的 INTERNAL 规则要靠评审 |
| sidecar 运行时（Dapr） | 语言中立的构件：状态、发布订阅、绑定 | 每个组件多一个进程；每个 sidecar 一个应用身份，外壳里的成员会丢掉各自的身份；管不到我们的 schema、角色和 outbox 规则 |
| WebAssembly 组件模型 | 一个沙箱运行时承载多种语言 | WASI 下的 PostgreSQL、gRPC、NATS 客户端都不成熟；没有主流 ERP 栈跑在它上面 |
| 一个原生核心库，绑进每门语言 | 难的部分只实现一次 | 每门语言一层 FFI；我们的镜像不开 cgo；各运行时的异步模型不同 |
| 每门语言各自约定，不做黑盒套件 | 不用写规范 | 语言之间的漂移要到生产上才发现 |

## 为什么选它

- **用户的要求（L1）**：每个组件可以自己选语言。规则住在某一门 SDK 里，那门语言就成了标准答案；规则放在独立仓库、配一套套件，就不会。
- **判行为而不是判代码**，对每门语言给出同一个判定，还能抓到读代码看不出来的问题：收了刷新令牌、池没有上限。
- **规范和向量用同一个版本号**，三门 SDK 和套件对"实现的是哪一套语义"没有分歧。
- **TypeScript 的栈，对照市场方案。** Fastify 5 而不是 Hono、Express 5 或 NestJS：它的钩子（onRequest、preHandler、onSend、onError、onTimeout）正好放下 SDK 的中间件链，每个成员一个实例天然隔离，还自带 pino 和 JSON Schema 校验；Hono 面向 Web 标准的 Request，在 Node 上服务端控制较弱；Express 没有钩子模型；NestJS 带来第二套写法。node-postgres 而不是 porsager/postgres、Kysely、Drizzle 或 Prisma：SDK 要在每个事务里 `SET LOCAL ROLE` 和 `search_path`，porsager 默认隐式缓存预编译语句，其余几个是查询构造器或 ORM（[0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md) 不用 ORM），Prisma 还做不到每个事务切角色。node-pg-migrate 保持纯 SQL，状态表放在组件自己的 schema 里。grpc-js 而不是 connect-node：connect-node 没有服务配置里的重试、重试预算，服务端也没有 `MaxConnectionAge`。

## 为什么不选其他

- **锁死语言**：正是 L1 要拿掉的限制。
- **Dapr**：单机上每个组件多一个进程，而外壳的单进程合并会把成员压成同一个应用身份。
- **WASM**：本项目要用的驱动还不能上生产。
- **原生核心库**：破坏不开 cgo 的镜像，核心里一次崩溃会连带每一门语言。
- **只有约定、没有套件**：不测的就会漂移；v0.5.0 三门 SDK 里查出的 45 条问题就是这种漂移。

## 什么时候换

- **协议表达不了某个语言生态必需的能力**（0105 改写后的重议条件）：可选的，在 minor 里扩展协议；变成必须的，在 major 里扩展。
- **一门语言出现第二个组件**：锁定它的栈（0103），决定要不要做官方 SDK。
- **同一门非官方语言的几个组件在单机上吃紧内存**：做官方 SDK 和启动器，再为这门语言建外壳仓库。
- 把两门语言合进一个进程永远不是一次"换"，见[已知限制](#已知限制)。

## 怎么换

- **用新语言写一个组件**：照[第四门语言](#第四门语言)做。动到的是这个组件自己的仓库、它的 `assembly.yaml` 和 `BRICKKIT.md`，以及它的测试记录；别的组件都不动。
- **把一个组件换一门语言重写**：组件 ID、契约、schema、事件都不变；发一个新版本，附新的套件报告。如果原语言有外壳、新语言没有，部署文件把它移出外壳。
- **协议的 minor**：顺序见 [`be-protocol` 的仓库结构](#be-protocol-的仓库结构)；组件在自己升上去之前，一直按它声明的协议版本受测。
- **给一门新语言做官方 SDK**：达到第 6 步的门槛，再为这门语言建外壳仓库（[0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)）。

## 一致性测试

- **用例目录**按 profile 放在 `be-protocol` 和套件里。代表性的用例：迁移连跑两次都以 0 退出；缺必填键时以 78 退出并点名；停掉 PostgreSQL 后 `/healthz` 仍是 200；刷新令牌、`alg: none`、错 `iss`、错 `aud` 的令牌得到 401；随机授权组合下 List 与 Check 的结论一致；总线停着时命令照样成功，总线恢复后事件恰好送达一次；两个副本时每一行 outbox 只发布一次；随机身份下所有表的属主都是 `PG_OWNER_USER`，schema 之外没有任何对象；列出的成员没编译进来时，外壳停下并点名。
- **先见红。** 套件的自检断言：每个坏 widget 变体都恰好在它自己那条用例上失败。只有这样，绿才可信。
- **向量**不在任何套件里：每门官方 SDK 的单元测试读 `be-protocol` 的 `vectors/`，对它所消费的槽位族，还读该族契约的 `vectors/`；第四门语言 SHOULD。
- **与其他套件的分工**，都在 `tools/be-acceptance/conformance/<端口>/` 下：`component`（本协议，每个组件和外壳）；`authz` 和 `iam`（槽位族成员，[20](20-authorization-provider.md)、[21](21-identity-provider.md)）；`bus` 和 `lifecycle`（每门 SDK 内部的适配器，经各自的 widget 每门 SDK 跑一遍，[12](12-event-bus.md)、[09](09-data-lifecycle.md)）；`db`（引擎，[03](03-database.md)）；`blob`、`secret`、`search`（各自的端口）。
- **外壳**：widget 单独运行和在外壳里运行，黑盒结果完全相同。

## 相关决策

- [0109 规则写在语言中立的组件协议里，由黑盒套件检查](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md)：本文是它的完整分析。
- [0105 任何语言，一份协议](../02-decisions/01-architecture/0105-any-language-one-protocol.md)：两道关；JVM/CLR 的提醒；没有任何进程混用多门语言。
- [0103 每种语言内部一套锁定的技术栈](../02-decisions/01-architecture/0103-locked-stack-per-language.md)：上面那张栈表，含 TypeScript 后端一行，以及"一门语言出现第二个组件之前先锁栈"的规则。
- [0101 组件之间禁止 import](../02-decisions/01-architecture/0101-no-imports-between-components.md)：官方 SDK 和族契约包可以跨边界；协议的向量和 schema 是拷贝来的测试数据，不是代码。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：一个外壳一个 SDK 版本，以及启动器在启动时的核对。
- [0104 槽位族需要多种合理实现，而且没有依赖边](../02-decisions/01-architecture/0104-variants-become-slot-families.md)：协议按 major 引用的族契约（`contract: authz/2.x`）。

## 已知限制

- **没有任何进程混用多门语言。** 所用语言没有启动器的组件，永远单独运行。
- **INTERNAL 规则套件看不见。** 官方语言之外，它们只能靠评审，扫源码的门禁也不跑。
- **套件需要真的 PostgreSQL 和 NATS**，每个组件要跑几分钟；它在发版时跑，不是每次保存都跑。
- **`/readyz` 没接进探针**，要等 brickKit 支持 readiness 探针；它是 SHOULD。
- **TypeScript 有启动器但没有外壳仓库**，因为今天没有 TypeScript 组件进外壳。
- **JVM 或 CLR 组件每个进程要 256–512 MiB、启动要几秒**；在单机上，这是不选它的主要理由。
- **`be-protocol` 打出 v1.0.0 之前**，规范是候选版，还可能随 pilot 组件调整。
