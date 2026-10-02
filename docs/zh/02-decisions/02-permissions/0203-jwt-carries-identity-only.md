[English](../../../en/02-decisions/02-permissions/0203-jwt-carries-identity-only.md) · [中文](0203-jwt-carries-identity-only.md)

# 0203 token 只承载身份，`sub` 归平台所有

**状态**：为 3.0.0 修订（新的身份 claim、平台自有的 `sub`）；已决定，随 3.0.0 统一升级落地。

## 决策

应用 token 由已安装的 IAM 成员在 IdP 完成认证之后签发，只说明调用者是谁，别的什么都不带。token 里不放任何一个权限键；每个角色能做什么来自 bundle（[0202](0202-local-permission-bundle.md)）。

| Claim | 含义 |
|---|---|
| `iss`、`aud` | 平台签发者（`IAM_ISSUER`）和本部署（`TENANT_ID`）；两者都要校验 |
| `sub` | **平台**用户 id，一个 UUIDv7；IdP 自己的 subject 只存在 IAM 成员的关联表里 |
| `typ` | `access` 或 `refresh`；请求上只接受 `access` |
| `iat`、`nbf`、`exp`、`jti` | 标准字段；access token 有效 600 秒 |
| `tenant_id` | 租户（[0308](../03-contracts-and-data/0308-tenant-is-the-deployment.md)）；`org_id` 退役 |
| `roles`、`dept_path` | 登录和刷新时从授权 provider 解析 |
| `act`、`ceil`、`dg`、`azp` | 实际行事方、天花板 profile 码、委托授予 id、客户端（[0210](0210-delegation-and-impersonation.md)）；`ceil` 装的是 profile 码，从不是权限键 |
| `locale` | 用户的语言，供服务端文本使用 |

每个 SDK 用同样的方式验证：`alg` 取自 JWKS 公钥（`RS256`、`ES256` 或 `EdDSA`），`kid` 必填，校验 `iss`、`aud`、`exp`、`nbf` 和 `typ`。

## 理由

身份随用户数增长，策略随角色数增长，各放在能保持小的地方。超级管理员的全部权限键会撑爆 8 KB 的请求头上限：登录成功，之后每个请求都以 `431` 失败。放在 token 里的权限也只有 token 过期时才会变。`sub` 归平台所有，换 IdP 就不会改写任何 `owner_id`、角色分配或审计行。没有 `typ`，refresh token 能冒充 access token；没有 `iss` 和 `aud`，别的部署或别的签发者的 token 也会被接受。

## 挡下什么

- "把用户的权限 / scope 放进 JWT claims"
- 为了把权限键塞进 token 而用通配符或压缩方案
- 把功能开关或数据范围规则放进 token
- 在 IAM 成员的关联表之外，把 IdP 的 subject 当用户 id 用
- 接受没有 `typ: access` 的 token，或 `iss`、`aud` 对不上的 token
- 在前端根据 token claims 判定访问权限，并把它当成安全措施

## 何时重新讨论

对权限键永不重新讨论。新增身份 claim 没问题，前提是项目支持的每一种 IAM 实现都能签发它。

完整分析：[21-identity-provider.md，端口契约](../../04-foundations/21-identity-provider.md#端口契约)。
