[English](../../en/04-foundations/18-edge.md) · [中文](18-edge.md)

# 边缘层

浏览器、移动端或外部系统与组件 REST 端口之间的一切：路由从哪来；请求进出时边缘对它做什么、绝不做什么；同一张路由表怎么在 Docker 上变成 Traefik 配置、在 Kubernetes 上变成 Ingress 或 Gateway API 对象。读者是要加一条公网路径、改网关、规划对外 API，或者想提议把鉴权挪到网关的人。

## 范围

- **覆盖：** TLS 终结；按路径前缀路由；中立的路由表及其生成器；边缘的请求体上限、超时和粗粒度限流；请求 ID 和 trace 的起点；剥掉客户端不该带的头；CORS；对外 API 的 API key 将在哪里限流；边缘的 HTTP 缓存；BFF 的取舍；浏览器怎么到达对象存储。
- **不覆盖：** token 验签和授权，它们留在每个服务里（[21-identity-provider.md](21-identity-provider.md)、[20-authorization-provider.md](20-authorization-provider.md)）；用户请求与错误的形状（[15-user-api-and-errors.md](15-user-api-and-errors.md)）；路由截止时间和服务端超时（[16-deadlines-and-retries.md](16-deadlines-and-retries.md)）；gRPC，它从不经过边缘（[14-system-rpc.md](14-system-rpc.md)）；系统内部的 trace 传播（[23-observability.md](23-observability.md)）；部署文件怎么生成（`brickkit docs 01-three-layers/03-deploy-yaml`）。

## 选择

- **路由由声明派生，绝不手写。** 每个组件在自己 `assembly.yaml` 的 `edge_routes` 里声明公网路径。be-ops 读全部声明加上 `brickkit.yaml` 里的确切版本，写出一张中立的路由表 `build/edge/routes.json`。每种目标一个生成器把它渲染出来：Docker 和 Podman 上是 Traefik 的 file provider；Kubernetes 上是 Ingress（或 Gateway API 的 `HTTPRoute`）对象。生成的路由表与 `brickkit.yaml` 不一致时，门禁失败。
- **Traefik 是默认的边缘**：`make up` 已经部署了它，体量小，会监视 file provider 的目录，内建 OpenTelemetry tracing。
- **边缘负责**：TLS；按最长路径前缀路由；每条路由一个请求体上限；由路由截止时间推出的边缘超时；按 IP 的粗粒度限流；开启 trace 和请求 ID；剥掉内部头和可伪造的头；只在存在独立来源时才配 CORS 白名单。
- **边缘不负责**：充当唯一一道鉴权、授权、套用数据范围、按业务内容路由、重试非幂等请求、缓存 API 响应。每个服务自己验签，所以绕过边缘、或者单独部署一个组件，都不会让安全变弱（[0509](../02-decisions/05-runtime/0509-edge-only-routes.md)）。
- **永不路由的**：gRPC 端口；`/healthz`、`/readyz`、`/metrics`、`/_be/info`；组件有意不写进 `edge_routes` 的内部路径（`/authz/bundle`、JWKS、Casdoor webhook）。
- **BFF**：移动端保留 `infra/bff-mobile`；PC 前端直接调各组件的 REST，名称靠属主的 `BatchGet` 补全；没有 PC BFF。
- **默认同源**：前端和 API 经边缘共用一个主机名，所以不需要 CORS。静态资源由前端自己的容器带缓存头发出；边缘什么都不缓存。

**状态**：已就位：Traefik v3.0，带 Docker 和 file 两个 provider（`infra/traefik/`）；全部十四个组件都声明了 `edge_routes`。还没有任何东西读 `edge_routes`：file provider 的目录是空的，所以浏览器到组件的路由没有任何生成物，边缘也没有任何中间件（没有上限、没有超时、没有剥头）。已定（随 3.0.0 统一升级落地）：路由表、Traefik 和 Kubernetes Ingress 两个生成器、中间件集合、新鲜度门禁。以后：按 API key 限流（随对外 API）、跨边缘实例的全局限流、Gateway API 生成器。

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

### 路由表

`build/edge/routes.json`，生成物，绝不手改：

```json
{
  "version": 1,
  "source": { "brickkit_yaml_sha256": "…" },
  "routes": [
    { "path": "/erp/sales/", "component": "erp/sales", "version": "3.0.0",
      "service": "erp-sales-3-0-0", "port": 8084,
      "auth": "required", "body_limit": 1048576, "timeout_s": 20,
      "rate": { "per_ip_rps": 100, "burst": 200 } }
  ]
}
```

- `service` 是成员自己带版本的服务名，单跑、在外壳里、在 Kubernetes 上都能解析（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)、[27](27-shells.md#端口契约)）；绝不是外壳的名字。升一次版本路由表就变，这正是它必须生成的原因。
- 按最长前缀匹配；兜底的 `/` 排在最后。
- 两个已安装的组件声明同一个前缀时，生成失败，并点出两者的名字。
- `mode` 让它不运行的组件不贡献路由。

### 边缘设置

不按路由区分的东西放在一个项目文件里（计划中的 `infra/edge.yaml`，由 be-ops 读）：主机名和 TLS（Docker 上是证书文件或 ACME，Kubernetes 上是 `tlsSecret` 或 cert-manager）、生成器、默认限流、边缘前面受信任的代理、CORS 白名单、对象存储的主机名。默认值：

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
| 出 | 等响应头最多等路由的 `timeout_s`，之后答 504；带请求体的请求绝不重试 |
| 出 | 服务给的 `X-Request-Id`、`Retry-After`、`Deprecation`、`Sunset`、`X-Data-As-Of` 原样保留 |

边缘自己产生的回答（404、413、429、502、503、504）带平台的 problem 错误体（[15](15-user-api-and-errors.md#错误体)），由一个静态错误服务给出，`domain: be`，reason 用 `NOT_FOUND`、`BODY_TOO_LARGE`，以及平台表里的三个边缘 reason：`RATE_LIMITED`（`RESOURCE_EXHAUSTED`，429）、`UPSTREAM_UNAVAILABLE`（`UNAVAILABLE`，502 和 503）、`UPSTREAM_TIMEOUT`（`DEADLINE_EXCEEDED`，504）。

### 经边缘访问对象存储

浏览器用预签名 URL 上传和下载文件（[22-object-storage.md](22-object-storage.md#预签名-url)）。边缘把一个独立的主机名（例如 `files.<host>`）转发给对象存储，`Host` 头原样不动，不鉴权，不设请求体上限：签名本身就是授权，而签名覆盖了主机名。对象存储从不和 API 共用主机名，因为在它前面加路径前缀会破坏签名。

### 目标

| 目标 | 生成器 | 写出什么 |
|---|---|---|
| Docker、Podman | `traefik-file`（默认） | `infra/traefik/dynamic/routes.yml`：router、service 和中间件（请求体上限用 `buffering`，另有 `ratelimit`、`headers`、错误服务）；Traefik 监视这个目录，所以重新生成不用重启 |
| Kubernetes | `k8s-ingress` | 共用主机名的 Ingress 对象，每条路由一条 path 规则，外加控制器自己的限流对象（Traefik 的 `Middleware`，或 ingress-nginx 的注解），与 brickKit 生成的清单并列应用 |
| Kubernetes | `gateway-api`（以后） | `HTTPRoute` 对象；上限经实现方自己的 policy 设置 |

brickKit 1.1.0 只为 `expose: true` 的组件生成 Ingress，而且每个组件一个主机名；它没法让多个组件按路径共用一个主机名。在它支持之前（计划提功能请求），由 be-ops 写出这些对象，部署时一并应用。

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

- **派生胜过手写**：brickKit 自己的设计原则就拿手写网关配置当反例：版本一变，这份第二副本就静默失效。本项目的服务名带版本，这种失效是必然的。
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
- **brickKit 能按路径共用主机名了**：Kubernetes 的路由改由 brickKit 生成，不再由 be-ops 生成。

## 怎么换

- **换网关产品**：在边缘设置里改生成器，重新生成。路由表、各组件的声明和每个组件都不变；端到端套件必须对新边缘跑通。
- **全局限流器**：把限流服务加进基础设施，让生成器的限流中间件指向它；路由的 `rate` 取值不变。
- **API key**：限流中间件加一个 key 来源（API key 的标识，等它的形状在权限契约里定下来，[20](20-authorization-provider.md)）；路由和组件都不变。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/edge/`，对每个生成器各跑一遍：

- **黄金路由表**：一组固定的 `assembly.yaml` 加一份 `brickkit.yaml`，必须恰好生成期望的 `routes.json`，每个生成器也必须恰好生成期望的文件；升版本之后服务名随之改变；
- **端到端**，经过边缘：`auth: required` 的路由不带 token 答 401（由服务答）；未知路径 404；请求体超上限 413；突发超速率 429；每个响应都带 `X-Request-Id`；客户端伪造的 `X-Request-Id` 或 `be-caller` 永远到不了服务和它的日志；从外面访问不到 `/healthz`、`/metrics` 和 gRPC 端口；经对象存储主机名的预签名上传能成功。

先写成红的测试：be-ops "从 `assembly.yaml` 生成 Traefik 动态配置"（还没有生成器）、"组件升版本后服务名随之改变"；项目端到端："登录接口按 IP 超速率答 429"、"请求体超上限答 413"、"伪造的 `X-Request-Id` 进不了日志"。门禁（计划中的 `edge-routes-fresh`）：生成的路由表与 `brickkit.yaml` 不一致；先对一份过期的路由表跑红一次。

## 相关决策

- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：网关是官方镜像加配置。
- [0107 权限 bundle 与 token 公钥地址是共享变量](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：用成员自己的服务名，绝不用外壳的。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：BFF 和前端永不进外壳。
- [0201 不引入 Redis](../02-decisions/02-permissions/0201-no-redis.md)：限流在边缘，配额在 PostgreSQL。
- [0208 gRPC 是系统面，人用 REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md)：只路由 REST；gRPC 端口从不经过边缘。
- [0509 边缘只做路由，认证和授权留在服务里](../02-decisions/05-runtime/0509-edge-only-routes.md)：本文就是它的完整分析。
- 计划中、尚未编号："边缘路由由声明生成"。

## 已知限制

- **限流按边缘实例计数**；有两个实例时，在全局限流器出现之前，客户端能拿到两倍的额度。
- **族级前缀只容得下一个成员**：`/integration/im/**` 由 IM 成员声明，同时装两个 IM 成员就会撞车，直到每个成员声明自己的子前缀。
- **Kubernetes 的路由在 brickKit 之外生成**，直到 brickKit 能按路径共用主机名。
- **Traefik 的 dashboard 是不安全模式**（`api.insecure: true`），只用于开发；生产要么保护起来，要么关掉。
- **今天什么都没有生成**：生成器落地之前，公网路径只能靠临时配置才到得了组件。
