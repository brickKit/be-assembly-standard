[English](../../../en/02-decisions/05-runtime/0509-edge-only-routes.md) · [中文](0509-edge-only-routes.md)

# 0509 边缘只做路由，认证和授权留在服务里

**状态**：已决定，随 3.0.0 统一升级落地。为 brickKit 1.3 修订：路由生成进 brickKit 读的部署条目（Kubernetes 上是 `paths`，Docker 和 Podman 上是 Traefik `labels`），不再另写一份路由文件。

## 决策

边缘（默认是 Traefik）位于浏览器、移动端或外部系统与组件的 REST 端口之间。它只处理流量，不碰任何"谁能做什么"的判断：

| | 内容 |
|---|---|
| **边缘负责** | TLS；按最长路径前缀路由；每条路由一个请求体上限；由路由截止时间推出的边缘超时；按 IP 的粗粒度限流；开启 trace 和请求 ID；剥掉内部头和可伪造的头（`X-Request-Id`、`traceparent`、所有 `be-*` 头、不可信来源的 `X-Forwarded-*`）；只在存在独立来源时才配 CORS 白名单 |
| **边缘不负责** | 充当唯一一道鉴权、授权、套用数据范围、按业务内容路由、重试带请求体的请求、缓存 API 响应 |
| **边缘永不路由** | gRPC 端口；`/healthz`、`/readyz`、`/metrics`、`/_be/info`；标了 `x-be-internal: true` 的 OpenAPI 操作，即只有其他组件调用的提供方平面（authz 的 `/authz/v2/*`、iam 在 `/.well-known/*` 下的 JWKS），它们也不计入边缘路由覆盖门禁；组件有意不写进 `edge_routes` 的内部路径（Casdoor webhook） |

- 每个服务自己用本地 JWKS 验 token，自己判定路由的权限键、数据范围和可见性，不管前面有没有边缘。
- `edge_routes` 里路由的 `auth: required | none` 只表明意图、驱动端到端测试；服务照样自己强制执行。
- 边缘自己产生的回答（404、413、429、502、503、504）带平台的 problem 错误体，`domain: be`（`RATE_LIMITED`、`UPSTREAM_UNAVAILABLE`、`UPSTREAM_TIMEOUT`）。
- **路由是生成的，从不手写。** be-ops 读每个组件的 `edge_routes`，把路由写进该组件的部署条目：Kubernetes 上是条目的 `paths`（brickKit 为每个组件生成一份 Ingress，前缀以路径段为界，共用一个 `hostname` 和一个 `tlsSecret`）；Docker 和 Podman 上是 Traefik 路由 `labels`，规则以路径段为界（``PathRegexp(`^/erp/sales(/|$)`)``，从不用按字符串匹配的裸 `PathPrefix`），由接在项目 `network:` 上的 Traefik 3.6 或更新版本读取（Docker Engine 29 拒绝旧版本请求的 API 版本）。标签和 Ingress 的后端跟着带版本的服务名走，所以升级不改任何路由。

## 理由

"每个组件都能独立运行"也包括前面没有我们的网关时照样运行：如果只在边缘验 token，绕过边缘、或单独部署一个组件，就等于全部敞开。每个服务自己验签代价很低（本地 JWKS 加本地权限 bundle，[0202](../02-permissions/0202-local-permission-bundle.md)），还多一层纵深防御。把业务判断挡在边缘之外，也让网关保持为基础设施而不是组件（[0106](../01-architecture/0106-infrastructure-is-not-a-component.md)）：官方镜像加生成的配置，换产品只需换一个生成器。

## 挡下什么

- 只在网关验 token（Traefik ForwardAuth、JWT 插件），再信任网关设置的某个头
- 在边缘判定权限键、数据范围、字段掩码或配额
- 按请求体或业务取值路由
- 把 gRPC、`/healthz`、`/readyz`、`/metrics`、`/_be/info` 或 `x-be-internal` 操作暴露到外部
- 在边缘重试非幂等请求；在边缘缓存 API 响应
- 为组件的用户面手写路由、Ingress 或 Traefik 规则；裸 `PathPrefix` 规则，它会让 `/erp/sales` 接走 `/erp/salesman`

## 何时重新讨论

客户的安全架构还要求在网关上再加一层认证时：它加在边缘前面，绝不取代服务里的验签。对外 API 开放后的按 API key 限流属于流量处理，不需要重新讨论。

完整分析：[18-edge.md，选择](../../04-foundations/18-edge.md#选择)。
