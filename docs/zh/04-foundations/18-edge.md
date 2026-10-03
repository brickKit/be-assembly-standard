[English](../../en/04-foundations/18-edge.md) · [中文](18-edge.md)

# 边缘层

浏览器、移动端或外部系统与组件 REST 端口之间的一切：路由从哪来；请求进出时边缘对它做什么、绝不做什么；同一组声明怎么在 Docker 和 Podman 上变成 Traefik 容器标签、在 Kubernetes 上变成 brickKit 的 Ingress 路径。读者是要加一条公网路径、改网关、规划对外 API，或者想提议把鉴权挪到网关的人。

## 范围

- **覆盖：** TLS 终结；按路径前缀路由；be-ops 怎么把路由声明变成部署条目的字段；边缘的请求体上限、超时和粗粒度限流；请求 ID 和 trace 的起点；剥掉客户端不该带的头；CORS；对外 API 的 API key 将在哪里限流；边缘的 HTTP 缓存；BFF 的取舍；浏览器怎么到达对象存储。
- **不覆盖：** token 验签和授权，它们留在每个服务里（[21-identity-provider.md](21-identity-provider.md)、[20-authorization-provider.md](20-authorization-provider.md)）；用户请求与错误的形状（[15-user-api-and-errors.md](15-user-api-and-errors.md)）；路由截止时间和服务端超时（[16-deadlines-and-retries.md](16-deadlines-and-retries.md)）；gRPC，它从不经过边缘（[14-system-rpc.md](14-system-rpc.md)）；系统内部的 trace 传播（[23-observability.md](23-observability.md)）；部署文件怎么生成（`brickkit docs 01-three-layers/03-deploy-yaml`）。

## 选择

- **路由由声明派生，绝不手写。** 每个组件在自己 `assembly.yaml` 的 `edge_routes` 里声明公网路径前缀，它 OpenAPI 契约里的每条路径都落在其中某个前缀之下。be-ops 把这些声明变成 brickKit 本来就读的部署条目字段，于是每个服务名和版本都由 brickKit 自己解析：
  - **Kubernetes**：条目的 `expose: true`、`hostname`、`tlsSecret` 和 `paths`（声明的前缀）。brickKit 为每个组件生成一份 Ingress（名为 `<scope>-<name>`，新版本滚动更新完成后才切过去），按路径段匹配，所以 `/erp/sales` 永远接不走 `/erp/salesman`。
  - **Docker 和 Podman**：条目上的 Traefik 路由 `labels`。规则以路径段为界，``Host(`app.example.com`) && PathRegexp(`^/erp/sales(/|$)`)``，从不用按字符串比较的裸 `PathPrefix`。Traefik 接到部署文件顶层 `network:` 指定的项目网络上，经 Docker provider 发现容器；标签跟着容器走。
  - 生成的字段与声明不一致，或某条 OpenAPI 路径不在任何声明的前缀之下时，门禁失败。标了 `x-be-internal: true` 的操作不计入这项覆盖检查，因为它们永不被路由。
  - 每个承载用户流量的操作都在 `x-be-permission` 里声明自己的守卫（一个权限键、`authenticated` 或 `public`）。缺少 `x-be-permission` 永远不算声明了守卫：该操作按受保护处理，契约门禁拒绝它（失败即关闭）。唯一的例外是标了 `x-be-internal: true` 的操作（提供方平面和运维端点），它不是用户流量，不需要 `x-be-permission`。
- **Traefik 是默认的边缘**：`make up` 已经部署了它（3.6 或更新版本：Docker Engine 29 拒绝旧版 Traefik 请求的 API 版本，3.3.7 就会失败），体量小，会发现带标签的容器，内建 OpenTelemetry tracing。Kubernetes 上，任何能合并同一主机多份 Ingress 的控制器都行（Traefik、nginx-ingress、HAProxy）。
- **边缘负责**：TLS；按最长路径前缀路由；每条路由一个请求体上限；由路由截止时间推出的边缘超时；按 IP 的粗粒度限流；开启 trace 和请求 ID；剥掉内部头和可伪造的头；只在存在独立来源时才配 CORS 白名单。
- **边缘不负责**：充当唯一一道鉴权、授权、套用数据范围、按业务内容路由、重试非幂等请求、缓存 API 响应。每个服务自己验签，所以绕过边缘、或者单独部署一个组件，都不会让安全变弱（[0509](../02-decisions/05-runtime/0509-edge-only-routes.md)）。
- **永不路由的**：gRPC 端口；`/healthz`、`/readyz`、`/metrics`、`/_be/info`；标了 `x-be-internal: true` 的每个 OpenAPI 操作，即只有其他组件调用的提供方平面（authz 的 `/authz/v2/*`、iam 的 `/.well-known/*`）；组件有意不写进 `edge_routes` 的内部路径（Casdoor webhook）。
- **BFF**：移动端保留 `infra/bff-mobile`；PC 前端直接调各组件的 REST，名称靠属主的 `BatchGet` 补全；没有 PC BFF。
- **默认同源**：前端和 API 经边缘共用一个主机名，所以不需要 CORS。静态资源由前端自己的容器带缓存头发出；边缘什么都不缓存。

**状态**：已就位：Traefik v3.0，带 Docker 和 file 两个 provider（`infra/traefik/`）；`deploy.yaml` 里的项目网络；全部十四个组件都声明了 `edge_routes`。还没有任何东西读 `edge_routes`，边缘也没有任何中间件（没有上限、没有超时、没有剥头）。brickKit 1.3 补上了本设计用到的两块平台能力：部署条目上的 `paths`（Kubernetes 上按路径共用一个主机名）和外壳替成员 `expose`；它按设计不在 Docker 上生成网关，推荐用 Traefik 标签。已定（随 3.0.0 统一升级落地）：Traefik 3.6 或更新版本、be-ops 生成 `paths` 和标签的生成器、中间件集合、新鲜度门禁。以后：按 API key 限流（随对外 API）、跨边缘实例的全局限流、Gateway API 生成器。

## 端口契约

### 声明

`assembly.yaml` 里的 `edge_routes`（本项目自己的文件，由 be-ops 读，brickKit 从不读）：

| 字段 | 必填 | 含义 |
|---|---|---|
| `path` | 是 | 以 `/**` 结尾的前缀，位于组件自己的前缀之下（`/erp/sales/**`），或者是预留的族前缀、平台前缀（`/api/iam/…`、`/integration/im/**`、`/graphql`）；前端的 `/**` 是兜底 |
| `auth` | 是 | `required` 或 `none`；记录意图，并驱动端到端测试；服务自己照样强制执行 |
| `body_limit` | 否 | 字节数；默认 1 MiB，与服务端的默认值相同（[16](16-deadlines-and-retries.md#逐跳的预算)） |
| `timeout` | 否 | 秒；默认取该组件这个前缀下所有 OpenAPI 操作里最长的 `x-be-deadline-seconds`（一个都没有时为 10 s），再加 5 s |
| `rate` | 否 | 每个客户端 IP 每秒的请求数和突发量，覆盖边缘对这个前缀的默认值 |

组件的资源契约路径（`/{domain}/{name}/_authz/*`、`/_shares/*`、`/_lifecycle/*`）都在它自己的前缀之下，所以随前缀一起路由（[20](20-authorization-provider.md#端口契约)）。

### be-ops 生成什么

be-ops 读每个已安装组件的 `edge_routes`，把前缀排好序，两个组件声明同一个前缀时拒绝生成（点出两者），再把下面这些字段写进每份部署文件（`deploy.yaml`、每一份 `deploy.<env>.yaml`）；它只拥有这些字段和 `traefik.*` 标签键，条目里别的东西一概不动。`mode` 让它不运行的组件什么都不贡献。

| 目标 | 写在组件条目上的字段 | `erp/sales`、前缀 `/erp/sales/**` 的例子 |
|---|---|---|
| Kubernetes | `expose: true`，来自边缘设置的 `hostname` 和 `tlsSecret`，`paths` | `paths: [/erp/sales]` |
| Docker、Podman | `labels`：每个前缀一个 router，service 指向组件的主端口，挂共享的中间件链和该路由自己的限制 | 见下 |

```yaml
# deploy.yaml（一个条目里生成的字段；target: docker）
- id: erp/sales
  labels:
    traefik.enable: "true"
    traefik.http.routers.erp-sales-0.rule: Host(`app.example.com`) && PathRegexp(`^/erp/sales(/|$)`)
    traefik.http.routers.erp-sales-0.priority: "10"              # 前缀长度：最长前缀优先
    traefik.http.routers.erp-sales-0.service: erp-sales
    traefik.http.routers.erp-sales-0.middlewares: be-edge@file,erp-sales-0-limits
    traefik.http.middlewares.erp-sales-0-limits.buffering.maxRequestBodyBytes: "1048576"
    traefik.http.services.erp-sales.loadbalancer.server.port: "8084"
```

- router 和 service 的名字是 `<scope>-<name>`，从不带版本；Traefik 按容器在项目网络上的地址找到它：升级不改任何标签。Kubernetes 上，Ingress 后面那个带版本的 Service 由 brickKit 自己填。
- **外壳成员。** 外壳承载成员期间，成员自己的 `labels` 不生效，所以 be-ops 把成员的 router 既写在成员自己的条目上（它单跑时用），也写在外壳的条目上、service 端口用成员的端口（外壳运行时用）；两个容器同一时刻只存在一个。Kubernetes 上，成员的 `expose`、`hostname` 和 `paths` 经外壳生效：成员有自己的 Ingress，指向它自己的 Service，而这个 Service 选中的是外壳的 Pod（[27](27-shells.md#端口契约)）。
- **同一个主机，一张证书。** Kubernetes 上，共用边缘主机名的每个条目带同一个 `tlsSecret`；同一主机下同一条路径写两次，brickKit 拒绝并点出两个组件。
- 前端声明 `/**`：Kubernetes 上它的条目不写 `paths`（整个主机，"其余一切"），Docker 上它的 router 优先级最低。

### 边缘设置

不按路由区分的东西放在一个项目文件里（计划中的 `infra/edge.yaml`，由 be-ops 读）：主机名和 TLS（Docker 上是证书文件或 ACME，Kubernetes 上是 `tlsSecret` 或 cert-manager）、默认限流、边缘前面受信任的代理、CORS 白名单、对象存储的主机名。be-ops 由它渲染出共享的中间件链 `be-edge`（剥头、请求 ID、默认限流、错误服务）：Docker 上是一份 Traefik file provider 文件，里面不出现任何服务名，所以永不过时；Kubernetes 上是部署文件的 `k8s.ingressAnnotations`，由 brickKit 写到每一份 Ingress 上。默认值：

| 设置 | 默认 |
|---|---|
| 限流，所有路由 | 每个客户端 IP 每秒 100 个请求，突发 200 |
| 限流，`/api/iam/*` | 每个客户端 IP 每秒 10 个请求，突发 20（登录和 token 端点） |
| 读客户端请求的超时 | 整个请求 30 s（与服务端相同，[16](16-deadlines-and-retries.md)） |
| 空闲连接 | 120 s |
| CORS | 关；只有存在独立来源（H5 子域、合作方）时才配来源白名单 |

### 边缘对每个请求做什么

| 方向 | 动作 |
|---|---|
| 进 | 丢掉客户端带来的 `X-Request-Id`、`traceparent`、`tracestate`、`baggage` 和所有 `be-*` 头；用自己的值替换 `X-Forwarded-For`、`X-Forwarded-Proto`、`X-Forwarded-Host`（只保留受信任代理给的） |
| 进 | 打开了边缘 tracing 时由边缘开启 trace；服务随后用 trace id 当请求 ID（[23](23-observability.md#端口契约)） |
| 进 | 请求体超过路由的 `body_limit` 答 413，速率超过路由的 `rate` 答 429，未知路径答 404 |
| 出 | 等响应头最多等路由的 `timeout`，之后答 504；带请求体的请求绝不重试 |
| 出 | 服务给的 `X-Request-Id`、`Retry-After`、`Deprecation`、`Sunset`、`X-Data-As-Of` 原样保留 |

**Traefik 上按路由设超时。** Traefik 只从 `serversTransport` 读取响应头超时，而 `serversTransport` 只有 file provider 能定义：标签设不了超时。所以 be-ops 把每条路由的超时写成生成出来的 file provider 文件（`infra/traefik/dynamic/edge.yml`）里的一个 `serversTransport`，路由所用服务的标签只按名字引用它。transport 属于服务而不属于路由器，所以一个前缀的超时如果和同组件其他前缀不同，就需要一个自己的服务。

边缘自己产生的回答（404、413、429、502、503、504）带平台的 problem 错误体（[15](15-user-api-and-errors.md#错误体)），由一个静态错误服务给出，`domain: be`，reason 用 `NOT_FOUND`、`BODY_TOO_LARGE`，以及平台表里的三个边缘 reason：`RATE_LIMITED`（`RESOURCE_EXHAUSTED`，429）、`UPSTREAM_UNAVAILABLE`（`UNAVAILABLE`，502 和 503）、`UPSTREAM_TIMEOUT`（`DEADLINE_EXCEEDED`，504）。

### 经边缘访问对象存储

浏览器用预签名 URL 上传和下载文件（[22-object-storage.md](22-object-storage.md#预签名-url)）。边缘把一个独立的主机名（例如 `files.<host>`）转发给对象存储，`Host` 头原样不动，不鉴权，不设请求体上限：签名本身就是授权，而签名覆盖了主机名。对象存储从不和 API 共用主机名，因为在它前面加路径前缀会破坏签名。

### 目标

| 目标 | be-ops 写什么 | brickKit 据此生成什么 | 上限与限流 |
|---|---|---|---|
| Docker、Podman | 每个条目上的 Traefik 路由 `labels`；放 `be-edge` 链和各路由 `serversTransports` 的 `infra/traefik/dynamic/edge.yml` | 原样写出的容器标签；项目网络标成 `external`，`up` 之前先核对它存在 | 按路由：请求体上限和速率写在标签里（`buffering`、`ratelimit`），超时写在 file provider 的 `serversTransport` 里 |
| Kubernetes | 每个条目上的 `expose`、`hostname`、`tlsSecret`、`paths`；共享链写进 `k8s.ingressAnnotations` | 每个组件一份 Ingress，名为 `<scope>-<name>`；Service 端口的 `appProtocol` 取自声明的 `protocol` | 共享注解引用的控制器自有对象（Traefik 的 `Middleware`，或 ingress-nginx 的注解）；所有路由一样 |
| Kubernetes | `gateway-api`（以后） | be-ops 写出的 `HTTPRoute` 对象 | 实现方自己的 policy |

每条用户面路径都在自己的前缀之下提供：边缘从不改写路径，请求到达组件时和浏览器发出时一样。

## 备选方案

| | Traefik（选用） | nginx | Envoy Gateway | APISIX / Kong | Caddy | 云 API 网关 / 负载均衡 |
|---|---|---|---|---|---|---|
| 单机资源 | 小 | 最小 | 中 | 中（要 etcd 或 PostgreSQL） | 小 | 不占本机 |
| 动态配置 | Docker、file、Kubernetes provider，监视变化 | 要 reload | xDS、Gateway API | Admin API | API、文件 | 控制台或 API |
| 限流 | 每实例，内存里 | `limit_req`，每实例 | 本地，加一个额外服务可做全局 | 插件，多种后端 | 插件 | 内建，全局 |
| Kubernetes | IngressRoute、Ingress、Gateway API | ingress-nginx | 原生 Gateway API | Ingress、CRD | 社区 | 云厂商自己的 |
| OpenTelemetry | 内建 | 模块 | 内建 | 插件 | 内建 | 不一 |
| 适合 | 单机到小集群 | 统一用 nginx 的客户 | 多节点且要全局限流 | 带门户的 API 产品 | 小站点 | 已经在某朵云上的客户 |

另有两个取舍问题，各有各的选项：

| 问题 | 选项 | 好处 | 代价 |
|---|---|---|---|
| token 在哪验 | 每个服务里（选用） | 单独部署时依然安全；纵深防御 | 每个服务都要验签（本地 JWKS，很便宜） |
| | 只在边缘（ForwardAuth、JWT 插件） | 一处 | 绕过边缘或单独部署组件时一切敞开 |
| BFF | 只给移动端一个（选用） | 手机需要聚合和更小的载荷 | PC 每页要多发几个请求 |
| | 每个渠道一个，含 PC | 每页一个请求 | 多一层聚合，要跟着每个组件一起改 |

## 为什么选它

- **派生胜过手写**：brickKit 自己的设计原则就拿手写网关配置当反例：版本一变，这份第二副本就静默失效。本项目的服务名带版本，这种失效是必然的，所以生成的字段里不出现任何服务名：Kubernetes 上由 brickKit 解析，Docker 上由 Traefik 找到带标签的容器。
- **部署文件本来就归 brickKit 生成**：把路由写进它读的条目，Ingress 和容器就只有一个生成者，不必在 brickKit 的产物旁边再应用一套对象。
- **安全不依赖边缘。** "每个组件都能单独运行"包括前面没有我们的网关也能运行。
- **网关是基础设施，不是组件**（[0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)）：官方镜像加生成的配置，换产品就是换一个生成器。
- **Traefik 已经在了**，会监视 file provider、不用 reload，免费版就覆盖了全部中间件。

## 为什么不选其他

- **nginx**：最小，但改配置要 reload，限流同样是每实例的；作为一个生成器保留给指定要它的客户。
- **Envoy Gateway**：它的长处是全局限流，但要额外的限流服务，而且只有多个边缘实例时才划算。
- **APISIX 或 Kong**：为售卖 API 而生（门户、消费者管理）；多一个配置存储，网关从"配置"变成了"运维"。
- **Caddy**：简单，但 Kubernetes 支持弱，没有内建限流。
- **云网关**：对已在该云上的客户，放在边缘前面可以，但不能替代生成的路由，因为它要手工配置。
- **只在边缘鉴权**：违反原则 1。
- **PC BFF**：多一层，每次组件改动都要传到它，换来的只是省下几个并行请求。

## 什么时候换

- **多个边缘实例，并且有一个必须跨实例成立的限额**（防滥用、合同约定的配额）：全局限流器，也就是 Envoy Gateway 加它的限流服务，或者在前面加云网关。
- **对外 API 开放**（[15](15-user-api-and-errors.md#版本策略)）：在边缘按 API key 限流；配额留在服务里，按 key 在 PostgreSQL 的计数窗口里计，不上 Redis（[0201](../02-decisions/02-permissions/0201-no-redis.md)）。
- **客户统一用 nginx 或某个 Gateway API 控制器**：换成那个生成器。
- **客户集群的控制器给每份 Ingress 各建一个负载均衡器**（GKE 自带的那种）：它合并不了同一主机下各组件的 Ingress；这时 be-ops 为这个主机自己写一份 Ingress（或 `HTTPRoute`），条目不写 `expose`。

## 怎么换

- **换网关产品**：Kubernetes 上，任何能合并同一主机 Ingress 的控制器都行：改 `k8s.ingressClass` 和共享注解；Docker 上，带 Docker 标签 provider 的网关在 be-ops 里加一个它自己的标签渲染器。各组件的声明和每个组件都不变；端到端套件必须对新边缘跑通。
- **全局限流器**：把限流服务加进基础设施，让生成器的限流中间件指向它；路由的 `rate` 取值不变。
- **API key**：限流中间件加一个 key 来源（API key 的标识，等它的形状在权限契约里定下来，[20](20-authorization-provider.md)）；路由和组件都不变。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/edge/`，对每个生成器各跑一遍：

- **黄金部署字段**：一组固定的 `assembly.yaml` 加一份部署文件，每种目标必须恰好生成期望的 `paths`、`labels` 和注解；升版本不改任何生成的字段；外壳成员的 router 同时出现在它自己的条目和外壳的条目上；
- **端到端**，经过边缘：`auth: required` 的路由不带 token 答 401（由服务答）；未知路径 404；`/erp/salesman` 不会被路由到 `erp/sales`；请求体超上限 413；突发超速率 429；每个响应都带 `X-Request-Id`；客户端伪造的 `X-Request-Id` 或 `be-caller` 永远到不了服务和它的日志；从外面访问不到 `/healthz`、`/metrics` 和 gRPC 端口；经对象存储主机名的预签名上传能成功。

先写成红的测试：be-ops "从 `assembly.yaml` 生成 Traefik 标签和 Kubernetes `paths`"（还没有生成器）、"前缀以路径段为界"；项目端到端："登录接口按 IP 超速率答 429"、"请求体超上限答 413"、"伪造的 `X-Request-Id` 进不了日志"。门禁（计划中的 `edge-routes-fresh`）：部署文件里生成的字段与声明不一致，或某条 OpenAPI 路径不在任何声明的前缀之下；先对一份过期的部署文件跑红一次。

## 相关决策

- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：网关是官方镜像加配置。
- [0107 族成员的地址是 `$endpoint:` 引用](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：同一原则用在地址上，每个服务名都由 brickKit 解析。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：BFF 和前端永不进外壳。
- [0201 不引入 Redis](../02-decisions/02-permissions/0201-no-redis.md)：限流在边缘，配额在 PostgreSQL。
- [0208 gRPC 是系统面，人用 REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md)：只路由 REST；gRPC 端口从不经过边缘。
- [0509 边缘只做路由，认证和授权留在服务里](../02-decisions/05-runtime/0509-edge-only-routes.md)：本文就是它的完整分析，包括路由生成进部署条目这一条。

## 已知限制

- **限流按边缘实例计数**；有两个实例时，在全局限流器出现之前，客户端能拿到两倍的额度。
- **族级前缀只容得下一个成员**：`/integration/im/**` 由 IM 成员声明，同时装两个 IM 成员就会撞车，直到每个成员声明自己的子前缀。
- **Kubernetes 上按路由的上限其实不分路由。** brickKit 把 `k8s.ingressAnnotations` 写到每一份 Ingress 上，所以那里某条路由自己的 `body_limit` 或 `rate` 没法和默认值不同；Docker 上由标签携带。brickKit 若有按条目的注解字段就能补上（等测出它真的要紧，再提功能请求）。
- **每个组件一份 Ingress**，需要能合并同一主机多份 Ingress 的控制器（nginx-ingress、Traefik、HAProxy 可以；GKE 自带的控制器不行）。
- **生成的标签放在部署文件里。** 个人的 `deploy.local.yaml` 会整体取代 `deploy.yaml`，所以重新生成之后，用 `brickkit local refresh` 把新标签带进去。
- **较旧的 Traefik 连不上 Docker Engine 29**，它拒绝这些版本请求的 API 版本（3.3.7 就会失败）；在 Docker 29 上边缘需要 Traefik 3.6 或更新版本。`infra/` 里的开发环境仍然钉在 v3.0，等 3.0.0 统一升级时再改。
- **Traefik 的 dashboard 是不安全模式**（`api.insecure: true`），只用于开发；生产要么保护起来，要么关掉。
- **今天什么都没有生成**：生成器落地之前，公网路径只能靠临时配置才到得了组件。
