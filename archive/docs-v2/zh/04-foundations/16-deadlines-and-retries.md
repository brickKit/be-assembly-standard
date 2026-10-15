[English](../../en/04-foundations/16-deadlines-and-retries.md) · [中文](16-deadlines-and-retries.md)

# 截止时间与重试

一个请求在每一跳上能花多少时间：从用户点击，经边缘、组件、组件的数据库，到它调用的其他组件；哪些失败会重试、由哪一层重试、允许多少重试流量；以及让一个慢依赖耗不光整个组件或外壳的舱壁。读者是要设超时、写重试、加一个长耗时路由，或者想提议熔断器的人。

## 范围

- **覆盖：** 时间预算及其传递；HTTP 服务器的超时和请求体上限；每一层的重试规则；重试预算；作为舱壁的并发上限和连接预算。
- **不覆盖：** 事务级的超时和 `40001`/`40P01` 重试的细节（[10-local-transactions.md](10-local-transactions.md)）；事件重投的细节（[12-event-bus.md](12-event-bus.md#持久消费者)）；任务和 reconciler 的退避（[19-background-jobs.md](19-background-jobs.md)、[11-consistency-across-components.md](11-consistency-across-components.md)）；边缘自己的超时和限流（[18-edge.md](18-edge.md)）。

## 选择

- **每个请求都有截止时间，而且只会缩短**：它一路传下去，每一跳给子调用的时间都比自己手里的少。用 brickKit 的话说，你给依赖设的超时，必须短于你的调用方愿意等你的时间（`brickkit docs 09-patterns/04-service-calling`）。
- **用户能接受的默认值：** 普通操作 10 s；编排类操作（例如确认订单）15 s，在它的路由上声明；导出是异步的。
- **方法要不要重试只由契约决定**：一个 gRPC 方法只有在声明自己无副作用或幂等时才会重试，而且只在 `UNAVAILABLE` 时。
- **每个客户端 channel 一份重试预算**（TypeScript 里是每个进程、每个目标一份，见[逐层的重试](#逐层的重试)），把重试流量限制在正常流量的约 10 %，依赖大面积宕掉时完全停止重试。
- **用舱壁代替熔断器：** 每个（成员，依赖）一个并发上限，每个成员一个连接预算，再加上截止时间。
- **只有一层重试。** 代码绝不在一个本来就会重试的调用外面再包一层重试循环。

**状态**：已定；随组件协议和 3.0.0 统一升级落地。今天哪里都没有设超时：HTTP 服务器、数据库语句、gRPC 调用、BFF 的下游请求都没有。一个挂住的依赖就能把登录和整条移动端路径一起挂住。

## 端口契约

### 逐跳的预算

| 跳 | 默认值 | 规则 |
|---|---|---|
| 用户等待 | 10 s；声明过的编排 15 s；导出返回 202，作为任务完成 | 需要超过 10 s 的路由在它的 OpenAPI operation 里声明 `x-be-deadline-seconds`（计划中），让边缘、服务端和前端读的是同一个数字 |
| 边缘 | 路由截止时间 + 5 s | 从同一处声明配置（[18](18-edge.md)） |
| 入站 HTTP | 路由的截止时间 | 请求上下文从读到第一个字节起就带着它 |
| HTTP 服务器 | 读请求头 5 s；读 30 s；写 = 路由截止时间 + 5 s；空闲 120 s；请求体最多 1 MiB，除非路由声明了更多 | 单跑和外壳里取值相同；文件经预签名 URL 进对象存储，绝不经过组件的请求体 |
| 入站 gRPC | 调用方的 `grpc-timeout`；没有时 10 s | [14](14-system-rpc.md#服务端要求) |
| 一次出站调用 | `min(3 s, remaining − 50 ms)` | 剩余 50 ms 或更少时不发出调用：`DEADLINE_EXCEEDED` / `DEADLINE_BUDGET_EXHAUSTED`。确实需要更久的系统 rpc（关闭会计期间）作为方法 option 声明（计划中） |
| 数据库语句 | `min(5 s, remaining)`；锁等待 2 s；事务内空闲 30 s | 按事务设置（[10](10-local-transactions.md#端口契约)） |
| 事件处理函数 | 总线的确认等待（30 s）减 5 s | 本地写入预期在 1 s 内完成；有副作用的处理函数每 10 s 报告一次进度（[12](12-event-bus.md#持久消费者)） |
| 任务运行、reconciler 步骤 | 任务声明的超时 | [19](19-background-jobs.md#端口契约) |
| 前端 | 路由截止时间 + 5 s | 之后把操作显示为未完成；重试的写复用它的 `Idempotency-Key`（[15](15-user-api-and-errors.md#请求头)） |

**TypeScript 里的 HTTP 服务端设置。** Node 的选项和"HTTP 服务端"那一行不是一一对应的，所以 SDK 在 Fastify（5.12 或更高，带 `handlerTimeout` 的版本）上这样设：

| Fastify / Node 选项 | 值 | 实现的是那一行的哪个值 |
|---|---|---|
| `headersTimeout` | `5000` | 读请求头 5 s |
| `connectionsCheckingInterval` | `1000` | Node 只按这个周期检查 `headersTimeout` 和 `requestTimeout`（默认 30 s）；设成 1 s，5 s 的请求头上限才是真的 |
| `requestTimeout` | `30000` | 读 30 s |
| `keepAliveTimeout` | `120000` | 空闲 120 s |
| `handlerTimeout` | 路由的截止时间 | Fastify 自己答 `503`；SDK 的错误处理器把它改成 `504`、code `DEADLINE_EXCEEDED`，`request.signal` 同时取消下游调用和事务 |

SDK 的错误处理器从不读 `AsyncLocalStorage` 上下文：处理函数超时时它跑在定时器的上下文里，那里的上下文是空的，所以成员 ID 和 request ID 从 `request` 和闭包里取。

演算示例，确认订单（15 s）：sales 收到请求时有 15 s；它自己的每次读各拿 `min(5 s, remaining)`；对 inventory 的预留调用拿 `min(3 s, remaining − 50 ms)`，到达时 `grpc-timeout` 最多 3 s；inventory 的语句拿 `min(5 s, 那份剩余)`。sales 下面的任何东西都活不过用户的等待。

### 逐层的重试

| 层 | 重试什么 | 怎么重试 | 上限 |
|---|---|---|---|
| 数据库事务 | `40001`、`40P01` | 重跑事务体，`10 ms · 2^n` ± 抖动 | 3 次尝试（[10](10-local-transactions.md)） |
| gRPC，`idempotency_level` 为 `NO_SIDE_EFFECTS` 或 `IDEMPOTENT` 的方法 | `UNAVAILABLE` | 下面的 service config | 总共 3 次尝试（首发加最多 2 次重试），外加重试预算 |
| gRPC，其他方法 | 只重试从没离开过客户端的请求（gRPC 的透明重试） | gRPC 内置 | 一次 |
| 组件代用户发起的 REST 调用 | 连接被重置的 `GET` | 立即重试一次 | 一次 |
| 前端写 | 超时和 5xx | 用同一个 `Idempotency-Key` | 由页面决定；绝不换新键 |
| 事件 | 处理函数出错 | SDK 按 `EVENTS_BACKOFF` 的延迟 nak（默认 1 s … 1 h）；服务端不设退避 | `EVENTS_MAX_DELIVER` 次投递（默认 8），然后进死信（[12](12-event-bus.md#持久消费者)） |
| 入队的命令 | 处理函数出错 | worker 的退避列表 | 它的最大尝试次数，然后进尝试用尽的处理函数（[19](19-background-jobs.md)） |
| Reconciler | 处理函数出错 | 按条目退避 | 它的最大尝试次数，然后置为 `SUSPENDED` 并开一条待办（[11](11-consistency-across-components.md)） |

每个 SDK 为一个依赖的可重试方法生成的 service config（gRPC 的 service-config JSON 在每种语言里都一样）：

```json
{
  "methodConfig": [{
    "name": [{ "service": "erp.inventory.v1.InventoryService", "method": "GetReservationStatus" }],
    "retryPolicy": {
      "maxAttempts": 3,
      "initialBackoff": "0.05s",
      "maxBackoff": "0.5s",
      "backoffMultiplier": 2,
      "retryableStatusCodes": ["UNAVAILABLE"]
    }
  }],
  "retryThrottling": { "maxTokens": 10, "tokenRatio": 0.1 }
}
```

- `maxAttempts` 3 指总共 3 次尝试：首发加最多 2 次重试，每门语言都一样。
- `retryThrottling` 就是重试预算（`maxTokens` 10）。它在哪一级计数，取决于 gRPC 库：

  | 语言 | 预算按什么计数 | 什么时候回满 |
  |---|---|---|
  | Go、Python | 客户端 channel，也就是每个（成员，依赖，端口）一份（[14](14-system-rpc.md#客户端要求)），所以一个成员的重试风暴花不掉另一个成员的预算（[27-shells.md](27-shells.md)） | 每次 channel 的 resolver 更新时（DNS 重新解析，通常跟在 `GOAWAY` 之后） |
  | TypeScript（grpc-js） | 进程加规范化的目标字符串，通往同一目标的所有 channel 共用 | 重新解析时不回满 |

  今天唯一的 TypeScript 组件是移动端 BFF，它从不进外壳，所以它的进程就是一个成员；将来 TypeScript 组件若进外壳，SDK 在自己的拦截器里维护按成员的预算。"重试流量 ≤ 10 %" 是稳态上限，不是硬上限。
- 对冲（hedging，在第一份失败之前就发第二份）关闭。
- **嵌套的重试会相乘。** 三层、每层三次尝试，宕机期间最底层会收到 27 次调用，而这正是依赖最扛不住的时候。组件绝不在一个本来就会重试的运行时调用外面再加自己的重试循环；更高一层的重试（reconciler、重投的事件）使用同一个幂等键。

### 舱壁

| 资源 | 上限 | 到达上限时 |
|---|---|---|
| 每个（成员，依赖）的并发出站调用 | 64 | 立即以 `RESOURCE_EXHAUSTED` / `OUTBOUND_LIMIT` 失败；绝不排队 |
| 每个成员的数据库连接 | `PG_POOL_MAX`（默认 10） | 最多等 `PG_POOL_ACQUIRE_TIMEOUT`（5 s）或剩余截止时间，然后 `RESOURCE_EXHAUSTED` / `DB_POOL_EXHAUSTED`（[03-database.md](03-database.md)） |
| 每个订阅同时处理的消息 | 4，每个 durable 最多 256 条未确认 | broker 暂停后续投递（[12](12-event-bus.md#持久消费者)） |
| 每个成员的缓存内存 | 每个缓存各自声明 | 淘汰（[17-caching.md](17-caching.md)） |

## 备选方案

| 做法 | 谁在用 | 优点 | 缺点 |
|---|---|---|---|
| **截止时间预算、契约驱动的重试、重试预算、舱壁**（选定） | gRPC 自身的设计；Google SRE 实践 | 每一跳的最坏情况都有界；每个 gRPC 库都内置；确定、可测试 | 有一批数字要选，并保持一致 |
| 代码里的熔断器（Hystrix 风格、resilience4j、gobreaker、Polly） | Netflix 时代的 Java 服务、很多 .NET 团队 | 依赖不好时快速失败 | 要按依赖调参；半开状态的行为难测；在单实例上，"打开"说的只是截止时间已经说过的话 |
| 代理或网格里的离群检测（Envoy、Istio） | Kubernetes 平台 | 不写代码就能剔除坏副本 | 每个 pod 一个 sidecar；外壳对它来说是一个应用 |
| 对冲请求 | Google 的尾延迟研究 | 有副本时能削减尾延迟 | 负载翻倍；只有一个副本时毫无收益 |
| 自适应并发上限（Netflix concurrency-limits、Envoy adaptive concurrency） | 大规模集群 | 上限跟着实测延迟走 | 需要稳定的流量来学习；更难推理 |
| 每次调用一个固定超时、没有预算 | 大多数代码的默认做法 | 简单 | 子调用可能活得比调用方长；失败在用户放弃之后才到，而且没有 trace |

## 为什么选它

- **先是单机：** 每个组件只有一个实例时，熔断器没有什么可绕开的，代理也没有什么可剔除的。保护用户的是有界的等待（截止时间给的）和有界的损害（舱壁给的）。
- **多副本时也正确：** 重试预算和连接寿命轮换（[14](14-system-rpc.md#负载均衡)）在加副本后照样起作用，不需要新配置。
- **能不能重试由契约决定**，所以没有哪个开发者，不论是人还是 AI，需要逐个调用去判断重试是否安全。
- **在每种语言里都一样**，因为截止时间、重试策略和限流是 gRPC 规范的一部分，而不是某一个库的 API。

## 为什么不选其他

- **熔断器**增加按依赖的调参和测试很少触及的状态，只为了说"依赖宕了"，而在单实例上，截止时间加重试预算已经处理了这件事。
- **网格离群检测**每个 pod 需要一个 sidecar，并且在外壳里丢失成员身份。
- **对冲**在单实例上让负载翻倍，换不来延迟收益。
- **自适应上限**需要我们没有的流量规模来学习；固定上限是可预测的。
- **没有预算的固定超时**就是今天的失败模式最温和的版本：调用在调用方不再等待之后才结束。

## 什么时候换

- **多节点且观察到部分故障**（一些副本慢或失败，另一些正常）：加一个拦截器级的熔断器或客户端离群检测，同时上 headless 均衡。
- **一条有副本的读路径，并且实测有尾延迟问题：** 只对那个读方法启用对冲。
- **固定的出站上限对某个依赖明显不合适**（正常负载下就拒绝，或者在延迟崩溃前从不触发）：把那个依赖的上限改成自适应的。

## 怎么换

这些都在 SDK 的客户端链或生成的 service config 里：一个新拦截器，给一个方法加 `hedgingPolicy`，换一个限流器。组件代码、契约和版本锁定都不变；路由的截止时间只通过它的声明改变。

## 一致性测试

计划中，放在 `tools/be-acceptance/conformance/rpc/` 和 `tools/be-acceptance/conformance/userapi/` 里；除非另有注明，今天都是红的。

- 入站 HTTP 请求带着路由的截止时间，出站调用继承剩余的预算；
- 剩余 50 ms 或更少时出站调用不发出，以 `DEADLINE_BUDGET_EXHAUSTED` 失败；
- 没带截止时间的 gRPC 调用拿到默认值；
- 只有 `NO_SIDE_EFFECTS` 或 `IDEMPOTENT` 方法会重试，而且只在 `UNAVAILABLE` 时；
- 重试预算用完后，不再发生重试；
- 发请求头很慢的客户端在读请求头超时之后被断开（TypeScript 里在超时之后 1 s 的检查周期内）；
- 超过截止时间的路由在每门语言里都答 `504` `DEADLINE_EXCEEDED`（TypeScript 里是改写过的 `handlerTimeout`）；
- 对同一个依赖的第 65 个并发调用立即以 `OUTBOUND_LIMIT` 失败；
- 在外壳里，一个成员耗尽它的连接预算，另一个成员的延迟不变。

先写成红的组件测试：infra/authz 挂住时，infra/iam-casdoor 的登录在截止时间内失败（今天会一直等下去）；下游挂住时，infra/bff-mobile 在预算内返回 GraphQL 错误（今天会一直等下去）。门禁：`idempotency-level-scan`（[14](14-system-rpc.md#契约规则)）。

## 相关决策

- [0503 截止时间与重试预算](../02-decisions/05-runtime/0503-deadlines-and-retry-budgets.md)：本文是它的完整分析。
- [0201 不用 Redis，不设缓存服务器](../02-decisions/02-permissions/0201-no-redis.md)：没有用于全局上限的共享存储；跨请求的限流归边缘。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：外壳里预算和上限按成员划分。
- [0208 gRPC 是系统面，人用 REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md)：组件之间的 gRPC 在其规范里携带截止时间与重试策略。

## 已知限制

- **上限是按进程的。** 没有跨副本的全局限流；那要等边缘。
- **异步工作没有端到端的截止时间：** 一条事件或一个入队的命令每次尝试有界，总体上由它的最大尝试次数限定。
- **`x-be-deadline-seconds` 和按方法的 option 都是计划中的**；在它们出现之前，一个长路由的截止时间要在代码里和前端里分别设置。
- **每次调用 3 s 的上限**对重的系统调用可能太短，直到那个调用声明了自己的上限。
- **截止时间是相对时长**（`grpc-timeout`），所以机器之间的时钟不必一致；绝不发送绝对时间。
