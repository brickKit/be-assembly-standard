[English](../../../en/02-decisions/05-runtime/0509-edge-only-routes.md) · [中文](0509-edge-only-routes.md)

# 0509 边缘只做路由，认证和授权留在服务里

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

边缘（默认是 Traefik）位于浏览器、移动端或外部系统与组件的 REST 端口之间。它只处理流量，不碰任何"谁能做什么"的判断：

| | 内容 |
|---|---|
| **边缘负责** | TLS；按最长路径前缀路由；每条路由一个请求体上限；由路由截止时间推出的边缘超时；按 IP 的粗粒度限流；开启 trace 和请求 ID；剥掉内部头和可伪造的头（`X-Request-Id`、`traceparent`、所有 `be-*` 头、不可信来源的 `X-Forwarded-*`）；只在存在独立来源时才配 CORS 白名单 |
| **边缘不负责** | 充当唯一一道鉴权、授权、套用数据范围、按业务内容路由、重试带请求体的请求、缓存 API 响应 |
| **边缘永不路由** | gRPC 端口；`/healthz`、`/readyz`、`/metrics`、`/_be/info`；组件有意不写进 `edge_routes` 的内部路径（`/authz/bundle`、JWKS、Casdoor webhook） |

- 每个服务自己用本地 JWKS 验 token，自己判定路由的权限键、数据范围和可见性，不管前面有没有边缘。
- `edge_routes` 里路由的 `auth: required | none` 只表明意图、驱动端到端测试；服务照样自己强制执行。
- 边缘自己产生的回答（404、413、429、502、503、504）带平台的 problem 错误体，`domain: be`（`RATE_LIMITED`、`UPSTREAM_UNAVAILABLE`、`UPSTREAM_TIMEOUT`）。

## 理由

"每个组件都能独立运行"也包括前面没有我们的网关时照样运行：如果只在边缘验 token，绕过边缘、或单独部署一个组件，就等于全部敞开。每个服务自己验签代价很低（本地 JWKS 加本地权限 bundle，[0202](../02-permissions/0202-local-permission-bundle.md)），还多一层纵深防御。把业务判断挡在边缘之外，也让网关保持为基础设施而不是组件（[0106](../01-architecture/0106-infrastructure-is-not-a-component.md)）：官方镜像加生成的配置，换产品只需换一个生成器。

## 挡下什么

- 只在网关验 token（Traefik ForwardAuth、JWT 插件），再信任网关设置的某个头
- 在边缘判定权限键、数据范围、字段掩码或配额
- 按请求体或业务取值路由
- 把 gRPC、`/healthz`、`/readyz`、`/metrics` 或 `/_be/info` 暴露到外部
- 在边缘重试非幂等请求；在边缘缓存 API 响应

## 何时重新讨论

客户的安全架构还要求在网关上再加一层认证时：它加在边缘前面，绝不取代服务里的验签。对外 API 开放后的按 API key 限流属于流量处理，不需要重新讨论。

完整分析：[18-edge.md，选择](../../04-foundations/18-edge.md#选择)。
