[English](../../en/04-foundations/15-user-api-and-errors.md) · [中文](15-user-api-and-errors.md)

# 用户 API 与错误

人经由浏览器、移动端 BFF，以及以后的外部系统访问的 REST 面：请求头和响应头、幂等、分页、一致性提示、版本策略，以及 REST、gRPC、GraphQL 共用的同一套错误模型，外加每个组件一份的 reason 目录。读者是要加路由、要返回错误、要做前端错误处理，或者在规划外部 API 的人。

## 范围

- **覆盖：** 每一次面向用户、与具体业务无关的 HTTP 交互的形状；状态码；错误体及其 gRPC、GraphQL 形式；reason 目录；面向内部与外部调用方的版本策略。
- **不覆盖：** 一个路由要求哪个权限键、怎么声明（[02-backend.md](../01-conventions/02-backend.md#权限)）；授权提供方和服务账号（[20-authorization-provider.md](20-authorization-provider.md)）；token（[21-identity-provider.md](21-identity-provider.md)）；截止时间（[16-deadlines-and-retries.md](16-deadlines-and-retries.md)）；边缘的限流和路由（[18-edge.md](18-edge.md)）；错误的日志级别（[23-observability.md](23-observability.md)）；前端怎么用这一切（[03-frontend.md](../01-conventions/03-frontend.md)）。

## 选择

- **每个组件用 REST 加 OpenAPI 3**，挂在组件自己的前缀下（`/erp/sales/orders`），JSON 请求体，每个路由一个权限键。
- **错误是 RFC 9457 problem details**（`application/problem+json`），带上 Google AIP-193 `ErrorInfo` 的字段：一个给机器看的 `reason`、定义它的 `domain`，以及字符串 `metadata`。gRPC 用 `google.rpc.Status` 加 `ErrorInfo` 携带同一个对象；GraphQL 放在 `extensions` 里。一个错误穿过这三者都不变。
- **每个组件声明自己的 reason**，写在 `contracts/errors.yaml` 里，只追加，带每种前端语言的消息模板。由前端翻译；服务端不翻译。
- **内部错误绝不外泄**：只给一条通用消息和 trace ID，原始错误只进日志。
- **调用方看不到的记录回答 404，读和命令都一样**；403 的意思是"你看得到它，但你不能做这件事"。
- **`Idempotency-Key`** 是请求体里 `idempotency_key` 的请求头形式。
- **列表按不透明游标分页**，字段名用契约里已有的。
- **版本：** 同一个主版本内只做加法；破坏性变更是一个新的路径前缀，与旧的并存，用 `Deprecation` 和 `Sunset` 公告。

**状态**：带路由权限键的 REST 已就位。错误模型、目录、请求头集合和 404 规则已定，随组件协议和 3.0.0 统一升级落地，赶在依赖它们的 06c 前端工作之前。今天的错误体是 `{"error": "<中文消息>"}`，`INTERNAL` 错误会把原始的数据库消息带到浏览器，超出范围的命令回答 403。

## 端口契约

### 请求头

| 请求头 | 含义 |
|---|---|
| `Authorization: Bearer <token>` | 用户的 access token（[21](21-identity-provider.md)） |
| `Idempotency-Key` | 用于写：每个用户操作一个 UUIDv7，这个操作的每次重试都复用它；两者都在时必须等于请求体里的 `idempotency_key`，否则 `400 IDEMPOTENCY_MISMATCH`；按调用方划分命名空间，有效期 30 天（[11](11-consistency-across-components.md#被调方的命令幂等)） |
| `X-Request-Id` | 可选；没有时生成；在响应里原样返回 |
| `traceparent` | W3C trace 上下文，通常在边缘创建（[23](23-observability.md)） |
| `X-Authz-Revision` | 授权一致性令牌（[20](20-authorization-provider.md)） |

`Accept-Language` 不用来选错误文本：前端按目录渲染文本。

### 响应头

| 响应头 | 什么时候带 |
|---|---|
| `X-Request-Id` | 总是 |
| `X-Data-As-Of` | 读的是由另一个组件的事件派生出的视图时：已应用的最新一条事件的 `occurred_at`，RFC 3339（[11](11-consistency-across-components.md#读己之写)） |
| `Retry-After` | 随 429 和 503 一起，在错误带有重试延迟时 |
| `X-Authz-Consistency: stale` | 一个列表是用落后于所请求 revision 的授权投影过滤出来时（[20](20-authorization-provider.md)） |
| `Deprecation`、`Sunset`、`Link: <…>; rel="successor-version"` | 在计划移除的操作上 |

### 列表

- 请求：`page_size`（每个端点有上限；超过上限就降到上限）和 `cursor`。响应：条目和 `next_cursor`，到末尾时为空。这些是契约里已经在用的名字；语义遵循 AIP-158。
- 游标是不透明的：它编码排序键、最后一个 ID 和过滤条件的哈希。带着不同过滤条件发来的游标以 `400 CURSOR_INVALID` 失败。
- 没有 `offset`，没有精确总数（[0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)）。

### 访问相关的状态码

| 情形 | 读 | 命令 |
|---|---|---|
| 没有 token，或 token 无效 | 401 `TOKEN_INVALID` | 401 |
| token 签发于用户角色变更之前 | 401 `TOKEN_STALE`；前端刷新后重试一次 | 同左 |
| 缺少路由的权限键 | 403 `MISSING_PERMISSION`，`metadata.permission` 写明是哪个键 | 同左 |
| 记录不存在 | 404 `NOT_FOUND` | 404 |
| 记录存在，但调用方经任何规则、分享或关系都看不到它 | 404 `NOT_FOUND`，与上一行无法区分 | 404 |
| 看得到，但这个操作需要调用方没有的键（对一条只分享查看权的记录） | — | 403 `MISSING_PERMISSION` |
| 看得到，调用方也持有这个操作的键，但这条记录不在这个键的范围内 | — | 403 `OUT_OF_SCOPE` |
| 请求参数本身就是一个维度取值，且不在调用方的范围内（`warehouse_id=7`） | 403 `OUT_OF_SCOPE` | 403 `OUT_OF_SCOPE` |
| 看得到也允许，但状态不允许 | — | 400 `FAILED_PRECONDITION`，带组件自己的 reason（`ORDER_NOT_DRAFT`） |
| 权限 bundle 还没加载，且路由不是 Public（Authenticated 路由也算） | 503 `AUTHZ_NOT_READY` | 503 |

**检查的顺序。** 路由守卫按固定顺序判定，同一个请求永远得到同一个回答：

1. Public 路由直接放行；
2. 校验令牌（格式、算法、密钥与签名、各 claim 的类型、`iss`、`aud`、`typ`、`sub`、`exp`/`nbf`/`iat`、`jti`）：令牌缺失或无效回答 401 `TOKEN_INVALID`，bundle 还没加载时也是这样；
3. 还没有加载任何 bundle：对每一个非 Public 路由回答 503 `AUTHZ_NOT_READY`；
4. bundle 里的令牌检查，按授权契约规定的顺序：令牌签发早于用户角色变更，或者带着一个已撤销的委托授予，回答 401 `TOKEN_STALE`；然后，委托令牌需要提供方具备 `delegation` 能力，参与者链里有 agent 需要 `agents`，一个用户代另一个用户操作（模拟登录）需要 `impersonation`，否则回答 401 `UNSUPPORTED_DELEGATION`（[21](21-identity-provider.md)、[0210](../02-decisions/02-permissions/0210-delegation-and-impersonation.md)）。所以过期判定先于委托判定；
5. Authenticated 路由放行；
6. 路由的权限键（叠加各层上限之后）：缺少则 403 `MISSING_PERMISSION`。

有一种回答可以早于以上全部：请求体超过路由的上限时，可以在守卫运行之前、也就是认证之前，以 413 `BODY_TOO_LARGE` 拒绝；这时它的访问日志行不带 `sub` 和 `perm`。

### 错误体

```json
{
  "type": "urn:be:erp/inventory:INSUFFICIENT_STOCK",
  "title": "Insufficient stock",
  "status": 400,
  "code": "FAILED_PRECONDITION",
  "reason": "INSUFFICIENT_STOCK",
  "domain": "erp/inventory",
  "detail": "Only 2 of product 0192… in stock, 5 requested",
  "metadata": { "product_id": "0192…", "requested": "5", "available": "2" },
  "violations": [ { "field": "items[0].qty", "reason": "MUST_BE_POSITIVE", "description": "…" } ],
  "instance": "/erp/sales/orders/0192…/confirm",
  "request_id": "…",
  "trace_id": "…"
}
```

| 字段 | 规则 |
|---|---|
| `type` | `urn:be:<domain>:<reason>` |
| `title` | 这个 reason 的短标题，用部署的默认语言（`DEFAULT_LOCALE`，默认 `zh-CN`），取自目录 |
| `status` | HTTP 状态码 |
| `code` | 标准的 gRPC code 名 |
| `reason`、`domain` | 错误的身份：前端用 `domain` + `reason` 去目录里查。`domain` 是组件 ID，平台 reason 则是 `be`；槽位族的成员不用自己的 ID，而用族的 ID（每个授权成员都回答 `domain: infra/authz`），这样前端每个族只维护一张表 |
| `detail` | 用 `DEFAULT_LOCALE` 渲染好的消息，供日志和调试；只在前端不认识这个 reason 时才展示给用户 |
| `metadata` | 只有字符串值，即模板的参数；绝不含用户自己发来的内容之外的个人数据，绝不含密钥 |
| `violations` | 字段错误，来自 gRPC 的 `BadRequest` |
| `instance` | 请求路径 |
| `request_id`、`trace_id` | 总是有 |

- **`INTERNAL`、`UNKNOWN` 和 `DATA_LOSS`** 一律回答 `reason: INTERNAL`、`domain: be`、一条通用的 `detail` 和 `trace_id`；原始错误只进日志。运行时的映射强制这一点；组件代码无法选择不用。
- **转发依赖的错误：** 依赖用它自己的 `ErrorInfo` 回答了，就原样转发：它的 `reason` 和 `domain` 对用户有意义时（库存不足）就保留；只有你添加了含义时，才映射成你自己的 reason。
- **依赖根本没有回答**，这不是依赖的错误，而是本次请求的错误：运行时回答 503 `DEPENDENCY_UNAVAILABLE`，由 `metadata.dependency` 指明是哪个依赖（见下面的目录）。
- **请求无法解码**，或者不符合操作的 schema（JSON 格式错误、类型不对、缺少必填字段、未知的枚举值、路径或查询参数格式不对，例如 UUID 不合法或十进制字符串格式错误），回答 400 `REQUEST_INVALID`，字段错误放在 `violations` 里。运行时的请求解码会抛它，组件自己对请求形状的校验也抛它。
- **调用方取消的请求**（客户端关闭了连接、gRPC 客户端取消）回答 499 `REQUEST_CANCELLED`，PostgreSQL 把这次取消报成 SQLSTATE `57014` 时也一样。它从不按错误记日志，访问日志行的级别是 info。运行时产生的每一个非 OK 回答都带 reason，所以一次取消绝不会变成 `INTERNAL` 和 500。

### gRPC 形式

status code，加上作为 message 的默认语言 `detail`，再加上 details：`ErrorInfo{reason, domain, metadata}` 总是有；字段错误用 `BadRequest`；有用时加 `PreconditionFailure`、`ResourceInfo`；`RetryInfo` 变成 `Retry-After`。不用 `LocalizedMessage`。运行时双向映射，所以一个组件经 gRPC 调用另一个组件、再经 REST 回答自己的用户，什么都不会丢。

| gRPC code | HTTP | gRPC code | HTTP |
|---|---|---|---|
| `INVALID_ARGUMENT`、`FAILED_PRECONDITION`、`OUT_OF_RANGE` | 400 | `RESOURCE_EXHAUSTED` | 429 |
| `UNAUTHENTICATED` | 401 | `CANCELLED` | 499 |
| `PERMISSION_DENIED` | 403 | `UNIMPLEMENTED` | 501 |
| `NOT_FOUND` | 404 | `UNAVAILABLE` | 503 |
| `ALREADY_EXISTS`、`ABORTED` | 409 | `DEADLINE_EXCEEDED` | 504 |
| `INTERNAL`、`UNKNOWN`、`DATA_LOSS` | 500 | | |

两个例外：`BODY_TOO_LARGE`（`INVALID_ARGUMENT`）回答 413；由边缘抛出的 `UPSTREAM_UNAVAILABLE`（`UNAVAILABLE`）回答 502 或 503。

### GraphQL 形式（移动端 BFF）

`errors[].extensions = { code, reason, domain, metadata, request_id, trace_id }`，从下游错误复制过来。

### reason 目录

```yaml
# contracts/errors.yaml
domain: erp/inventory
reasons:
  - reason: INSUFFICIENT_STOCK
    code: FAILED_PRECONDITION
    http: 400
    params: [product_id, requested, available]
    title:   { en: "Insufficient stock", zh: "库存不足" }
    message: { en: "Only {available} of {product_id} in stock, {requested} requested",
               zh: "{product_id} 库存只有 {available}，需要 {requested}" }
    since: 3.0.0
    deprecated: false
```

- `reason` 是 `UPPER_SNAKE`，在 domain 内唯一。槽位族成员的 reason 列在族契约的 `errors.yaml` 里，归在族的 domain（`infra/authz`）下，不进成员自己的目录。条目**只追加**，和 `registry/permissions.tsv` 一样：绝不改名、删除或复用；用 `deprecated: true` 退役（[07-registries.md](../01-conventions/07-registries.md#只追加)）。
- 前端从已安装组件的目录生成自己的消息表，就像它从契约生成类型一样。不认识的 reason 显示 `title` 或一条通用消息，并上报。
- **平台 reason** 用 `domain: be`，随组件协议一起发布（`brickKit/be-protocol` 的 `schemas/errors-be.yaml`，[02](02-languages-and-component-protocol.md#be-protocol-的仓库结构)）。下表是完整集合，共 36 个 reason，与该文件逐行一致；组件不在自己的 domain 里使用这些名字，也不抛该文件之外的 `be` reason：

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
| `MISSING_CALLER` | `UNAUTHENTICATED` | 系统面调用没带 `be-caller`（[14](14-system-rpc.md)） |
| `OUT_OF_SCOPE` | `PERMISSION_DENIED` | 请求参数本身就是一个维度取值，且不在调用方的范围内（`warehouse_id=7`）；或者一条看得到的记录，不在调用方所持操作键的范围内（[20](20-authorization-provider.md)） |
| `FIELD_FORBIDDEN` | `PERMISSION_DENIED` | 写了一个调用方看不到的字段 |
| `SORT_FORBIDDEN` | `INVALID_ARGUMENT` | 按对调用方掩码的字段排序、过滤或聚合 |
| `SHARE_NOT_ALLOWED` | `PERMISSION_DENIED` | 这个资源类型或这个调用方不允许做的分享（[20](20-authorization-provider.md)） |
| `CAPABILITY_UNAVAILABLE` | `UNIMPLEMENTED` | 装的 provider 或适配器缺某项能力；`metadata.capability` 写明是哪项 |
| `IDEMPOTENCY_MISMATCH` | `INVALID_ARGUMENT` | 一个键被复用在别的命令、目标或请求体上 |
| `IDEMPOTENCY_IN_PROGRESS` | `ABORTED` | 这个键的第一次使用还没结束 |
| `CURSOR_INVALID` | `INVALID_ARGUMENT` | 游标与请求不匹配 |
| `BATCH_TOO_LARGE` | `INVALID_ARGUMENT` | ID 数超过一个批次允许的数量 |
| `LOCK_TIMEOUT` | `ABORTED` | 锁等待超过了 `lock_timeout`（[10](10-local-transactions.md#端口契约)） |
| `STATEMENT_TIMEOUT` | `DEADLINE_EXCEEDED` | 一条语句或一个事务超过了它的超时 |
| `TX_CONFLICT` | `ABORTED` | 自动重试之后序列化失败仍然存在 |
| `DB_POOL_EXHAUSTED` | `RESOURCE_EXHAUSTED` | 成员的连接预算一直满到截止时间 |
| `OUTBOUND_LIMIT` | `RESOURCE_EXHAUSTED` | 对同一个依赖的并发调用太多（[16](16-deadlines-and-retries.md)） |
| `DEADLINE_BUDGET_EXHAUSTED` | `DEADLINE_EXCEEDED` | 剩余时间太少，不足以发起调用 |
| `BODY_TOO_LARGE` | `INVALID_ARGUMENT` | 请求体超过路由的上限；以 HTTP 413 回答（[16](16-deadlines-and-retries.md)） |
| `RANGE_COLD` | `FAILED_PRECONDITION` | 请求的时间范围已转入冷存储；`metadata` 给出冷区间，以及能否解冻、能否异步导出 |
| `UNIT_SEALED` | `FAILED_PRECONDITION` | 修改一个已封存的生命周期单元；应当新建一张冲销单据 |
| `RATE_LIMITED` | `RESOURCE_EXHAUSTED` | 只由边缘抛出：达到了调用方或路由的限流上限；HTTP 429，带 `Retry-After`（[18](18-edge.md)） |
| `UPSTREAM_UNAVAILABLE` | `UNAVAILABLE` | 只由边缘抛出：边缘连不上组件；HTTP 502 或 503（[18](18-edge.md)） |
| `UPSTREAM_TIMEOUT` | `DEADLINE_EXCEEDED` | 只由边缘抛出：组件没在边缘的截止时间内回答；HTTP 504（[18](18-edge.md)） |
| `NETWORK_IN_TX` | `INTERNAL` | 事务打开期间发起了出站调用：属于编程错误，在日志和测试运行里写明这个名字，好让它们抓到；调用方收到的仍是上面所说的 `reason: INTERNAL`（[10](10-local-transactions.md#端口契约)、[0501](../02-decisions/05-runtime/0501-no-network-inside-a-transaction.md)） |
| `DB_TOO_MANY_CONNECTIONS` | `UNAVAILABLE` | 数据库以 SQLSTATE `53300`（连接过多）拒绝了连接；不重试 |
| `NESTED_TX` | `INTERNAL` | 在同一个工作单元里、一个事务内又打开了另一个事务：属于编程错误，在日志和测试运行里写明这个名字；调用方收到的仍是上面所说的 `reason: INTERNAL`（[10](10-local-transactions.md#端口契约)） |
| `REQUEST_INVALID` | `INVALID_ARGUMENT` | 请求无法解码，或者不符合操作的 schema（JSON 格式错误、类型不对、缺少必填字段、未知的枚举值、路径或查询参数格式不对，例如 UUID 不合法、十进制字符串格式错误）；字段错误放在 `violations` 里 |
| `DEPENDENCY_UNAVAILABLE` | `UNAVAILABLE` | 运行时连不上本次请求需要的东西；`metadata.dependency` 取 `db`（PostgreSQL：连不上、连接断开、SQLSTATE `08` 类、`57P01`、`57P02`、`57P03`）、`bus`（事件总线，直接发布时）、`blob`（对象存储），或者没有回答的那个依赖的组件 ID 或槽位族 ID（连接被拒绝或重置，或者回答了 `UNAVAILABLE` 却没有自己的 `ErrorInfo`）；HTTP 503 |
| `REQUEST_CANCELLED` | `CANCELLED` | 调用方取消了请求（客户端关闭连接、gRPC 客户端取消），包括这种取消引起的 SQLSTATE `57014`；HTTP 499；从不按错误记日志 |

三个边缘 reason 绝不由组件抛出：边缘自己产生的回答（404、413、429、502、503、504）带同样的 problem 体，`domain: be`。

**哪种"不可用"用在哪里。** 三种情况看起来相似，要分开：

- 边缘连不上组件，或者组件没有在时限内回答：`UPSTREAM_UNAVAILABLE` 或 `UPSTREAM_TIMEOUT`，只由边缘抛出，组件和它的运行时从不抛；
- 组件连不上自己的数据库、总线、对象存储或另一个组件：`DEPENDENCY_UNAVAILABLE`，由该组件的运行时抛出，`metadata.dependency` 说明是哪一个。数据库因为连接过多而拒绝连接时，保留它自己的 reason `DB_TOO_MANY_CONNECTIONS`；
- 依赖用它自己的错误（`ErrorInfo`）回答了，包括 `UNAVAILABLE`：原样转发，保留依赖的 `reason` 和 `domain`。

### 版本策略

- **同一个主版本内，操作只增不减**（[0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)）；`make contract-check` 拒绝破坏性的 OpenAPI 变更。
- **破坏性变更**（罕见，由人决定）把新操作发布在一个新前缀 `/<domain>/<name>/v2/…` 下，与旧操作并存。旧操作的响应带 `Deprecation` 和 `Sunset`，只在 sunset 日期之后才移除。
- **外部调用方**（外部 API 在路线图上）：同样的规则就是公开的承诺。服务账号和 API key 是授权契约里的主体（[20](20-authorization-provider.md)）；按 key 的限流在边缘执行；开发者门户和配额界面以后再做。

## 备选方案

| 做法 | 优点 | 缺点 |
|---|---|---|
| **RFC 9457 携带 AIP-193 字段，外加 reason 目录**（选定） | 一个每个 HTTP 客户端都认识的 IETF media type；允许扩展成员；与 gRPC 的 `ErrorInfo` 是同一个 reason；可测试、可翻译 | 每个组件要维护一份目录 |
| 简单的 `{code, message, details}` 错误体 | 简单 | 不是标准；每个客户端各自发明解析方式 |
| Google 的 JSON 错误（`{"error": {code, status, message, details}}`） | `google.rpc.Status` 的 1:1 呈现 | 绑定 Google 网关的惯例；通用 HTTP 工具对它的熟悉程度不如 RFC 9457 |
| 不带目录的 RFC 9457（随意的 `type` URI 和 `detail` 文本） | 没什么要维护 | 前端只能显示服务端的文本；没有东西可以拿来测试 reason |
| 服务端按 `Accept-Language` 翻译 | 客户端拿到什么就显示什么 | 每个组件都要维护每种语言的文本；语言切换是前端偏好（[0404](../02-decisions/04-frontend/0404-four-user-preferences.md)） |
| 整个用户面用 GraphQL 或 OData | 查询灵活 | 路由级权限键和边缘的按路径路由难得多；每个组件里多一种查询语言 |

## 为什么选它

- **端到端只有一个错误对象：** 在 inventory 里抛出的 reason，经 sales 的 REST 回答到达浏览器，或经 BFF 的 GraphQL 到达手机，不用在每一跳重新发明。
- **机器 reason 让错误可测试**（测试断言 `CUSTOMER_CODE_TAKEN`，而不是一句话），也**能在前端翻译**，而用户的语言本来就归前端管。
- **从构造上就没有内部信息外泄**，因为 `INTERNAL` 这一情形归运行时的映射管。
- **对不可见的记录回答 404**，让命令无法试探一条记录是否存在。

## 为什么不选其他

- **自造的错误体**会让每种语言的每个客户端又多学一种形状。
- **Google 的 JSON 形式**：一旦 AIP-193 的字段成了 RFC 9457 的成员，它提供的东西 RFC 9457 都有。
- **随意的 problem details** 让前端只剩下一种语言的服务端文本。
- **服务端翻译**把每种语言的文本都塞进每个组件，并且与"语言是前端偏好"冲突。服务端只在没有前端参与的地方渲染文本：通知和打印单据，用接收者的语言。
- **处处用 GraphQL 或 OData**，是拿按路由的权限键和简单路由去换没有哪个组件需要的查询灵活性；GraphQL 只留在移动端 BFF。

## 什么时候换

- **外部 API 开放：** 加上 API key、配额和公开的版本承诺，不改错误模型，也不改路径。
- **合作方要客户端库：** 从 OpenAPI 契约生成。
- **通知和打印之外也需要服务端文本：** 在 gRPC details 里加 `LocalizedMessage`，并加一个对应的 problem 成员，作为一次加法。

## 怎么换

- 新的错误字段、请求头或 reason 是对协议和目录的加法；忽略它们的客户端照常工作。
- 对一个操作的破坏性变更是一个新路径前缀，如上所述；错误体本身预计不会变。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/userapi/`，对一个运行中的组件做黑盒测试：

- `INTERNAL` 错误不含原始文本，并带 `trace_id`（今天是红的）；
- 一个 `ErrorInfo` 变成 problem 错误体，再变回同一个 `ErrorInfo`；`BadRequest` 变成 `violations`；`RetryInfo` 变成 `Retry-After`；
- 不可见的记录对读和命令都回答 404；缺少键回答 403 `MISSING_PERMISSION`；
- `Idempotency-Key` 和请求体字段可互换；不一致时回答 400 `IDEMPOTENCY_MISMATCH`；
- 换了过滤条件复用的游标回答 400 `CURSOR_INVALID`；超过上限的 `page_size` 被降下来；
- 每个响应都带 `X-Request-Id`。

门禁（计划中的 `error-catalog-scan`）：代码里用了但目录里没有的 reason 失败；已发布的 reason 被从目录里删掉失败。组件样例：mdm/customer 对重复的编码回答 `CUSTOMER_CODE_TAKEN`。前端 FE-1：不认识的 reason 回退到 `title` 并上报。

## 相关决策

- [0504 一种错误对象，由目录里的 reason 标识](../02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md)：本文是它的完整分析。
- [0212 调用者看不见的记录答 404](../02-decisions/02-permissions/0212-invisible-records-answer-404.md)：调用方看不到的记录回答 404，命令也一样。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：版本策略，包括带 `Deprecation` 和 `Sunset` 的 `/v2/` 路径前缀。
- [0208 gRPC 是系统面，人用 REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md)：它的另一半：REST 是用户面。
- [0301 金额是与币种成对的十进制字符串；列表按游标分页](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)：金额与分页。
- [0204 权限是纯并集，没有 Deny](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md) 和 [0205 数据范围的规则随版本发布](../02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md)：403 和 404 依据它们来判定。
- [0404 用户偏好只有四项](../02-decisions/04-frontend/0404-four-user-preferences.md)：语言是前端偏好，所以由前端翻译。

## 已知限制

- **目录的完整程度取决于声明**；门禁抓得到代码里没声明的 reason，抓不到组件本该有却没有的 reason。
- **`metadata` 只放字符串**，与 AIP-193 一样；数字和日期由产生方格式化。
- **列表没有精确总数。**
- **404 只在回答里隐藏存在性，在耗时上不隐藏**；不尝试做等时响应。
- **外部 API 还没建**：key、配额和边缘限流已设计，未实现。
