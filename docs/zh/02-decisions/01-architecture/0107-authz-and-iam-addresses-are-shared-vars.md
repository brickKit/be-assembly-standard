[English](../../../en/02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md) · [中文](0107-authz-and-iam-addresses-are-shared-vars.md)

# 0107 授权与身份经共享变量访问，从不经依赖

**状态**：为 3.0.0 修订（`AUTHZ_URL` 取代 `AUTHZ_BUNDLE_URL`；新增 `IAM_ISSUER`、`TENANT_ID`；不对任何族成员建边）；已决定，随 3.0.0 统一升级落地。

## 决策

任何组件都不对授权族（[0209](../02-permissions/0209-authz-is-a-slot-family.md)）或身份族的成员声明依赖边。这两个族的全部契约，都经共享变量访问；这些变量在 `config/vars.yaml` 里写一次，以 `$var:NAME` 引用：

| 键 | 指向什么 |
|---|---|
| `AUTHZ_URL` | 已安装的 authz 成员：bundle、变更流、check、元组写入、`ResolveClaims`，族契约定义的一切 |
| `IAM_JWKS_URL` | 已安装 IAM 成员的签名公钥 |
| `IAM_ISSUER` | 每个 token 期望的 `iss`；它是平台的名字，不是 IdP 的 |
| `TENANT_ID` | 每个 token 期望的 `aud`（[0308](../03-contracts-and-data/0308-tenant-is-the-deployment.md)） |

主机名用成员自己带版本的服务名（`infra-authz-<版本>`、`infra-iam-casdoor-<版本>`），单跑、外壳内、Kubernetes 上都能解析，所以不需要任何部署文件覆盖它；它只在该成员发版时变化，与 `brickkit.yaml` 不一致时 `make gates` 失败（见[配置约定](../../01-conventions/04-configuration.md#依赖地址)）。族成员自己也一样：`infra/iam-casdoor` 到 `infra/authz` 的依赖边删除，iam 经 `AUTHZ_URL` 调用 authz。

## 理由

依赖钉的是精确版本，所以每个组件都对 authz 和 iam 建边，两者任何一次发版都会逼所有组件跟着发版。这两个位置都是槽位族：依赖边写死了一个实现（`INFRA_IAM_CASDOOR_ENDPOINT`），而槽位成员不能被依赖，换成员就要改每一个组件。组件用公开的公钥在本地验 token，对照本地 bundle 判定权限（[0202](../02-permissions/0202-local-permission-bundle.md)），所以不需要平台安排启动顺序。

## 挡下什么

- 把任何 authz 或 IAM 族成员写进 `dependencies.components`，包括从另一个族成员写
- 用注入的 `*_ENDPOINT` 变量拼 authz 或 IAM 的地址，或继续保留 `AUTHZ_BUNDLE_URL`
- 共享值适用时，仍在某个组件的 `config/<scope>-<name>.yaml` 里写死 authz 或 JWKS 的 URL
- 每个请求都调一次 IAM 组件来校验 token
- 指望平台先启动 authz 或 iam，再启动用到它们的组件
- 用外壳的服务名访问 authz 或 iam：它只在 Docker 上、成员被合并时存在，并随该外壳的每次发版变化
- 开启 Kubernetes `networkPolicy` 却没在部署文件里放行这些调用（对 authz、iam 的 Pod 加 `egress.allowTo`，对它们的入站加 `allowFrom`）：生成的策略只跟随依赖边，于是每个受保护路由都答 `503`

## 何时重新讨论

brickKit 提供一种对槽位（按位置而非成员）的依赖：既不钉精确版本，注入的变量里也不带实现的名字。

完整分析：[20-authorization-provider.md，端口契约](../../04-foundations/20-authorization-provider.md#端口契约)和 [21-identity-provider.md，端口契约](../../04-foundations/21-identity-provider.md#端口契约)。
