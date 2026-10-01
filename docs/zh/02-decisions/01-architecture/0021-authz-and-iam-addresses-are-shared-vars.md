[English](../../../en/02-decisions/01-architecture/0021-authz-and-iam-addresses-are-shared-vars.md) · [中文](0021-authz-and-iam-addresses-are-shared-vars.md)

# 0021 权限 bundle 与 token 公钥地址是共享变量，不是依赖

## 决策

每个组件都需要从 authz 和 iam 拿两样东西——轮询权限 bundle、验证 token——做这两件事时，组件不建依赖边。组件从 `AUTHZ_BUNDLE_URL` 读取 bundle 地址，从 `IAM_JWKS_URL` 读取身份提供方的签名公钥地址。两者都只在 `config/vars.yaml` 中设置一次，各组件的配置用 `$var:AUTHZ_BUNDLE_URL` / `$var:IAM_JWKS_URL` 引用。主机名是成员自己的版本化服务名（`infra-authz-<版本>`、`infra-iam-casdoor-<版本>`），独立运行、在外壳里、在 Kubernetes 上都能解析，所以没有部署文件覆盖它；它只在 authz 或 iam 发版时改，与 `brickkit.yaml` 对不上时 `make gates` 失败（见[配置约定](../../01-conventions/04-configuration.md#依赖地址)）。通过 gRPC 调用 authz 或 iam 业务接口的组件，与其他依赖一样声明这条依赖——例如 `infra/iam-casdoor` → `infra/authz`——注入的 `*_ENDPOINT` 只用于这类调用。

## 理由

依赖锁定的是精确版本。如果每个组件都对 authz 和 iam 建依赖边，它们任何一个发版都会迫使所有组件跟着发版。IAM 还是一个槽位：依赖边会把实现的名字带进变量（`INFRA_IAM_CASDOOR_ENDPOINT`），从 Casdoor 换到另一个 OIDC 提供方就要改每一个组件。组件用发布的公钥在本地验签，并且能容忍 authz 尚未启动（[0005](../02-permissions/0005-local-permission-bundle.md)），所以不需要平台为它们安排启动顺序。真正的业务调用不同：调用方依赖那个接口的契约，因此要像其他依赖一样锁定精确版本。

## 挡下什么

- 只是为了拉 bundle 或验证 token，就在 `dependencies.components` 下加 `infra/authz@x.y.z` 或 `infra/iam-casdoor@x.y.z`
- 用 `INFRA_AUTHZ_ENDPOINT` 或 `INFRA_IAM_CASDOOR_ENDPOINT` 拼 bundle 或 JWKS 地址，而不是用 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL`
- 不声明依赖就调用 authz 或 iam 的 gRPC 接口（比如把 `AUTHZ_BUNDLE_URL` 截掉路径来用）
- 共享值适用时，在某个组件的 `config/<scope>-<name>.yaml` 里写死 bundle 或 JWKS 的 URL
- 每个请求都调用 IAM 组件校验 token
- 指望平台先启动 authz 或 iam，再启动只拉 bundle 或只验 token 的组件
- 用外壳的服务名寻址 authz 或 iam：它只在 Docker 上、成员已合并时存在，而且外壳每发一版就变
- 开启 Kubernetes `networkPolicy` 却不在部署文件里放行这两类调用（authz 与 iam Pod 的 `egress.allowTo`，它们入站的 `allowFrom`）：生成的策略只按依赖边放行，每条受保护路由都会返回 `503`

## 何时重新讨论

brickKit 提供一种既不锁定精确版本、也不把实现名带进注入变量的依赖类型时。
