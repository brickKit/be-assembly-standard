[English](../../en/04-foundations/14-system-rpc.md) · [中文](14-system-rpc.md)

# 系统 RPC

组件之间怎么同步调用：gRPC 作为系统面；系统面上的调用方是谁；它能承载哪几类调用；连接怎么复用、怎么均衡；每次调用都带的 metadata；消息大小、压缩、流式、契约版本；以及同一个外壳里成员之间的调用。读者是要加 rpc、要调用别的组件、要用一门新语言实现组件协议，或者想提议换一种协议的人。

## 范围

- **覆盖：** 组件与组件之间的同步调用，包括线上形态和契约。
- **不覆盖：** 人（浏览器、移动端 BFF、外部系统）调用的接口：[15-user-api-and-errors.md](15-user-api-and-errors.md)。截止时间和重试的细节：[16-deadlines-and-retries.md](16-deadlines-and-retries.md)。status 里携带的错误详情：[15](15-user-api-and-errors.md#端口契约)。服务身份 token：[21-identity-provider.md](21-identity-provider.md)。代码里的使用规则：[02-backend.md](../01-conventions/02-backend.md#调用其他组件)。

## 选择

- **gRPC（HTTP/2 加 protobuf）是系统面。** 系统面上的每个调用方都是系统主体：同一个项目网络里的另一个组件。人从不调用 gRPC；按用户数据范围过滤的数据，只经 REST 读写。
- **系统面上只允许三类 rpc：** `data_scopes: none` 的数据（主数据）；系统协议（预留的 try、confirm 和 cancel，开待办，检查会计期间）；按 ID 补全（`BatchGet`），针对调用方正当持有的 ID，每次最多 500 个。
- **契约里已有的面向用户的 rpc 保留**（契约只增不减），在每个组件里都以同样的方式回答 `UNAUTHENTICATED`。
- **连接复用**，按（成员，依赖，端口）一条，带 keepalive；服务端每 5 分钟轮换连接，让负载在 Kubernetes 上摊开。
- **消息上限 4 MiB，不压缩，不用流式，包名带版本 `<domain>.<name>.v<n>`。**
- **地址来自 brickKit**：声明的依赖用端口名为 `grpc` 的注入 endpoint；槽位族成员用 `*_GRPC_URL` 键，填 `$endpoint:<成员>:grpc`。每个端口都在 `component.yaml` 里声明自己的 `protocol`。

**状态**：组件之间的 gRPC 已就位。连接复用、keepalive、截止时间、统一的身份拦截器和 metadata 集合已定，随组件协议和 3.0.0 统一升级落地。今天每次调用都新拨一条连接、用完就关；没有任何调用带截止时间、trace 上下文或调用方身份；面向用户的 rpc 回答 `UNAUTHENTICATED`、`INTERNAL` 还是直接成功，取决于是哪个组件。

## 端口契约

### 寻址

- brickKit 为每个声明的依赖注入 `<ID>_ENDPOINT`，一律带 `http://` 前缀，gRPC 端口也一样。运行时去掉 scheme，用名为 `grpc` 的额外端口（[02-backend.md](../01-conventions/02-backend.md#rt-是唯一入口)）。误拨到 HTTP 端口时，TCP 能连上，随后以协议错误失败。
- 缺席的可选依赖根本没有这个变量；调用方降级。
- **槽位族成员**（授权、身份）从不是依赖，所以没有 `*_ENDPOINT`。它的 gRPC 地址是自己的键 `AUTHZ_GRPC_URL` 或 `IAM_GRPC_URL`，在 `config/vars.yaml` 里填 `$endpoint:infra/authz:grpc`：brickKit 解析出成员名为 `grpc` 的端口，跟着升级和外壳走。运行时去掉 `http://`，拨 `host:port`。任何地址都不靠端口算术推出（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）。
- **端口协议。** 主端口写 `deployment.protocol: http`，名为 `grpc` 的额外端口写 `protocol: grpc`；brickKit 在 Kubernetes 上把它们写成 Service 端口的 `appProtocol`（集群认的词可以用 `k8s.appProtocols` 替换，例如 `kubernetes.io/h2c`），于是服务网格或 Gateway API 的实现按请求而不是按连接均衡 gRPC。Docker 上不生成什么，也不需要什么。
- 没有注册中心，除了这些变量之外没有服务发现。

### 请求 metadata

| 键 | 值 | 谁设置 | 用途 |
|---|---|---|---|
| `grpc-timeout` | 调用方剩余的预算 | 调用方运行时 | 被调方的截止时间（[16](16-deadlines-and-retries.md)） |
| `traceparent`、`tracestate` | W3C trace 上下文 | 调用方运行时 | 跨跳的同一条 trace（[23](23-observability.md)） |
| `x-request-id` | 入站请求的 ID，或新生成一个 | 调用方运行时 | 日志关联 |
| `be-caller` | 发起调用的组件 ID；在外壳里，是发起调用的成员的 ID | 调用方运行时 | 日志、审计、按调用方限流 |
| `be-actor-sub` | 引起这次调用的那个用户的平台 `sub`，**在调用时**从上下文里读出；后台工作没有这一项 | 调用方运行时 | 只用于审计（"由谁收到"） |
| `be-actor-act` | 代理链（token 的 `act` claim），JSON 形式，用户经代理方行事时才有 | 调用方运行时 | 只用于审计 |
| `authorization` | 留给服务 token（`sub: svc:<组件 ID>`），等组件跨信任边界运行时启用 | — | [21](21-identity-provider.md) 里的扩展点 |

`be-caller` 和 `be-actor-sub` 的可信程度和网络完全一样：能连到 gRPC 端口的任何东西本来就能调用它。它们只被记录，绝不用来授予访问权。因为连接是共享的，拨连接时不捕获任何关于用户的东西。

### 服务端要求

- 拦截器顺序，unary 和 streaming 相同：panic 恢复 → 身份（把这次调用标为系统主体，读 `be-caller` 和 `be-actor-sub`）→ 截止时间下限（调用方没发 `grpc-timeout` 时为 10 s）→ 批量上限 → 错误详情规范化（[15](15-user-api-and-errors.md#端口契约)）→ RED 指标 → tracing。
- 没带 `be-caller` 的调用回答 `UNAUTHENTICATED` / `MISSING_CALLER`。
- 为兼容而保留的面向用户的 rpc，由运行时在任何组件代码运行之前回答 `UNAUTHENTICATED`。
- `max receive message size` 4 MiB，显式设置。
- Keepalive：`max connection age` 5 分钟（`GRPC_MAX_CONNECTION_AGE`），宽限 30 s（`MaxConnectionAgeGrace`）；客户端 ping 的最小间隔 20 s（`MinTime`）；没有活跃调用时的 ping 一律拒绝。
- **宽限必须大于最长的入站截止时间**（30 s 对默认的 10 s 和编排路由的 15 s）；否则换连接时在途调用会被切断。
- **`MinTime` 只在 Go 和 Python 里强制。** grpc-js 服务端没有 keepalive 强制策略，所以 TypeScript 服务端没法强制 20 s 的下限；它的一致性测试声明跳过这条断言。
- 外壳里每个成员都有自己的 gRPC 服务器，在自己的端口上，用自己的拦截器链。

### 客户端要求

- 每个（成员，依赖，端口）一条连接，懒创建，所有调用复用，停止时关闭。
- Keepalive：有活跃调用时空闲 30 s 后 ping，超时 10 s；没有活跃调用时不 ping。
- 按每个方法的 `idempotency_level` 生成 service config（[16](16-deadlines-and-retries.md#端口契约)）：`maxAttempts` 3 指总共 3 次尝试（首发加最多 2 次重试），重试预算 `maxTokens` 10，在 Go 和 Python 里按每个成员的每个 channel 计数，在 TypeScript（grpc-js）里按进程和目标计数（[16](16-deadlines-and-retries.md#逐层的重试)）。
- 拦截器顺序：默认截止时间 → 出站并发上限 → metadata → 客户端 RED 指标 → 事务守卫（[10](10-local-transactions.md#端口契约)）。

### 契约规则

- 包名 `<domain>.<name>.v<n>`；改动只做加法（[0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)）；`buf breaking` 在 `make contract-check` 里跑。
- 每个方法都声明 `option idempotency_level`：读、`BatchGet` 和 `GetStatus` 用 `NO_SIDE_EFFECTS`；每个带 `idempotency_key` 的写用 `IDEMPOTENT`。有门禁检查（计划中的 `idempotency-level-scan`）。
- 每个聚合根都提供 `BatchGet`，每次最多 500 个 ID（上限作为方法 option 声明）；超过的以 `INVALID_ARGUMENT` / `BATCH_TOO_LARGE` 失败。每个跨组件写入都提供按键查询的 `GetStatus`（[11](11-consistency-across-components.md#被调方的命令幂等)）。
- 金额用十进制字符串，列表按游标分页（[0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)）。
- 不用流式 rpc。大结果写进对象存储，再用一条事件通知（claim check，[22-object-storage.md](22-object-storage.md#大结果)、[13](13-event-contracts.md#载荷规则)）。

### 负载均衡

- **Docker：** 每个组件或外壳一个容器；没什么可均衡的。
- **Kubernetes 且 `replicas > 1`：** brickKit 为每个组件生成一个 ClusterIP Service，kube-proxy 按 TCP 连接做均衡。一条被复用的 HTTP/2 连接会永远停在一个 pod 上；服务端 5 分钟的连接寿命到了就发 `GOAWAY`，客户端重连，落到一个重新选出的 pod 上，所以负载大约五分钟内就会均匀。不用 mesh，不用 xDS。
- **以后，测出需要时：** brickKit 不做 headless 伴生 Service（FR06-008：客户端负载均衡是组件自己的选择，而那个变量在 Docker 下没有对应物）。按请求均衡那时由读取 brickKit 所写 `appProtocol` 的服务网格或网关提供；第一次试用时记下用的网格、写的词和每个 Pod 的请求数。

### 外壳里

- 成员之间的调用和单跑时完全一样走网络：注入的 endpoint 指向外壳的服务和该成员的端口，解析回同一个容器（在 Docker 上约 0.1 ms）。
- 没有进程内传输：它会跳过序列化和拦截器，让成员合并时和单跑时行为不同（[0101](../02-decisions/01-architecture/0101-no-imports-between-components.md)、[0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)）。
- 连接和上限都按成员划分，所以 `be-caller` 写的是真实的调用方，一个成员的突发流量也用不到另一个成员的预算（[27-shells.md](27-shells.md)）。
- 外壳重启会让所有成员同时宕掉；调用方看到的是一次共同的抖动，由截止时间和重试预算吸收。

## 备选方案

| | gRPC（选定） | 组件之间用 REST + OpenAPI | Connect-RPC | Twirp | GraphQL | 只用消息 | 服务网格（Linkerd、Istio） |
|---|---|---|---|---|---|---|---|
| 契约 | proto，强类型，有破坏性变更检查 | OpenAPI | proto，与 gRPC 同一批文件 | proto | SDL | 事件 schema | —（叠加在某个协议之上） |
| 截止时间、重试、均衡 | 内置在协议及其 service config 里 | 手写 | 截止时间有；重试和均衡手写 | 没有 | 手写 | 不适用 | 在 sidecar 里 |
| 语言 | 几乎所有语言都有生成的客户端 | 所有语言 | Go 和 TypeScript 成熟，Python 还年轻 | Go 优先 | TypeScript 成熟 | 所有语言 | 所有语言 |
| 浏览器能否直接调用 | 不能（要 gRPC-Web） | 能 | 能 | 能 | 能 | 不能 | — |
| 调试 | `grpcurl` | `curl` | `curl` | `curl` | 工具 | broker 工具 | — |
| 在这里的代价 | 没有新增 | 组件之间类型更弱 | 第二种线上格式 | 缺功能 | 多一层 schema | 每个读都变成异步 | 每个 pod 一个 sidecar；外壳对它来说是一个应用 |

## 为什么选它

- **难的部分由协议承担**：截止时间（`grpc-timeout`）、带预算的重试、keepalive 和负载均衡，规范只定一次，每个 gRPC 库都实现了，所以任何语言的组件都是靠配置而不是写代码拿到它们。
- **带破坏性变更检查的强类型契约**正合"契约只增不减"。
- **一条较弱的模型也能遵守的规则：** 人用 REST，组件用 gRPC。安全边界就是传输方式。

## 为什么不选其他

- **Connect-RPC：** 它的优势是浏览器能调用同一份 proto，而这恰恰是系统面禁止的；它的 Python 实现还年轻。它留作逃生口：connect-go 服务器也说 gRPC 线上协议。
- **Twirp：** 没有截止时间、没有重试、没有均衡。
- **组件之间用 REST：** 每一个截止时间、重试和类型检查，都得我们在每种语言里自己做。
- **GraphQL：** 只在客户端要聚合很多数据源时有用，那是移动端 BFF 的事，不是组件的事。
- **只用消息：** 等着看"缺货"的用户没法等一条事件（[11](11-consistency-across-components.md#选择)）。
- **网格：** 每个 pod 一个 sidecar，违背"没有网关、没有网格"；而且外壳对它来说是一个应用，成员身份就丢了。

## 什么时候换

- **浏览器必须直接调用 proto**（这会重新打开系统面这条决策）：用 connect-go handler 提供同一批契约。
- **多节点且出现部分故障**（一些副本坏了、另一些正常）：经 `appProtocol: grpc` 按请求均衡的服务网格，加离群检测。
- **组件跨信任边界**（别的组织的网络、不受信任的对端）：先在 `authorization` 上用服务 token，再上双向 TLS。

## 怎么换

- **Connect-go：** 改的是 SDK 里的服务端 handler；客户端和契约不变。
- **Headless 均衡：** 一处部署改动，加上客户端 target `dns:///<service>:<port>`，在生成的 service config 里用 `round_robin`；不动组件代码。
- **服务 token：** 身份提供方签发 client-credential token，身份拦截器校验它；metadata 键和组件 API 保持不变。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/rpc/`，对每个官方 SDK 跑；今天大多数用例是红的。

- 对同一个依赖的一百次调用用的是同一条连接；
- 没带截止时间的调用拿到默认值；被调方看到的是调用方剩余的预算；
- 只有 `NO_SIDE_EFFECTS` 和 `IDEMPOTENT` 方法会重试，而且只在 `UNAVAILABLE` 时；重试预算用完后，重试停止；
- 一个 `ErrorInfo` 经 gRPC → REST → gRPC 后不变（[15](15-user-api-and-errors.md)）；
- `traceparent`、`x-request-id`、`be-caller` 和 `be-actor-sub` 到达被调方；在外壳里，`be-caller` 是发起调用的成员；
- 超过 4 MiB 的消息在两端都明确失败；
- 到了服务端的最大连接寿命后，客户端重连，不会有失败的调用，带着最长入站截止时间的在途调用也不会失败；
- ping 比每 20 s 一次更频繁的客户端被断开（Go 和 Python；TypeScript 上跳过）；
- 没带用户调用面向用户的 rpc，回答 `UNAUTHENTICATED`，而不是 `INTERNAL`。

先写成红的组件测试：erp/inventory 和 crm/opportunity 的面向用户 rpc 回答 `UNAUTHENTICATED`（今天是 `INTERNAL`）；mdm/customer 和 mdm/product 拒绝没带用户的 gRPC 写入（今天会成功）；外壳组装好之后，在同一个外壳里 sales → inventory 的 `Reserve` 把确认订单的用户记为操作人。门禁：带 `idempotency_key` 却没有 `IDEMPOTENT` 的方法失败，先在样例上看到红。

## 相关决策

- [0208 gRPC 是系统面，人用 REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md)：本文是它的完整分析。
- [0304 `BatchGet` 最多 500 个 ID](../02-decisions/03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md)：一次 `BatchGet` 最多 500 个 ID。
- [0101 组件之间禁止 import](../02-decisions/01-architecture/0101-no-imports-between-components.md) 和 [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：外壳里的调用也走网络。
- [0107 族成员的地址是共享变量里的 `$endpoint:` 引用](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：不对 authz 或 IAM 成员建边，它们的 gRPC 端口经 `*_GRPC_URL`；其他调用都声明依赖。
- [0503 截止时间与重试预算](../02-decisions/05-runtime/0503-deadlines-and-retry-budgets.md)：系统面上的截止时间与重试预算。
- [0301 金额是与币种成对的十进制字符串；列表按游标分页](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) 和 [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：字段规则和演进规则。

## 已知限制

- **系统面信任网络。** gRPC 端口绝不经边缘路由，Kubernetes 部署会加网络策略；跨信任边界之前必须先有服务 token。
- **`be-actor-sub` 不经校验**；它适合审计，不适合做判定。
- **扩容后重新均衡最多要大约五分钟**，在用 ClusterIP Service 时。
- **不用流式，上限 4 MiB**：大批量传输走对象存储。
- **外壳重启对它的所有成员是同一次故障。**
