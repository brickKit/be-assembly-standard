[English](../../../en/02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md) · [中文](0107-authz-and-iam-addresses-are-shared-vars.md)

# 0107 族成员的地址是共享变量里的 `$endpoint:` 引用，从不经依赖

**状态**：为 3.0.0 修订过两次：先是 `AUTHZ_URL` 取代 `AUTHZ_BUNDLE_URL`、新增 `IAM_ISSUER` 与 `TENANT_ID`、任何组件都不对族成员建边；再是随 brickKit 1.2，地址的值改为 `$endpoint:` 引用、不再手写服务名，每个 gRPC 地址有自己的键，`service-hostname-scan` 门禁退役。已决定，随 3.0.0 统一升级落地。

## 决策

任何组件都不对授权族（[0209](../02-permissions/0209-authz-is-a-slot-family.md)）或身份族的成员声明依赖边。组件把自己读的族键写进 `configSchema`，以 `$var:NAME` 引用共享值。共享值只在 `config/vars.yaml` 里写一次，其中每个地址都是指向已安装成员的 brickKit `$endpoint:` 引用，从不手写主机名或端口：

```yaml
# config/vars.yaml：每个槽位由谁来填，只写在这里
AUTHZ_URL:      $endpoint:infra/authz
AUTHZ_GRPC_URL: $endpoint:infra/authz:grpc
IAM_URL:        $endpoint:infra/iam-casdoor
IAM_GRPC_URL:   $endpoint:infra/iam-casdoor:grpc
IAM_ISSUER:     urn:be:acme:iam
TENANT_ID:      acme
```

| 键 | 指向什么 |
|---|---|
| `AUTHZ_URL` | 已安装授权成员的主端口：bundle、变更流、check、元组写入，族 REST 契约定义的一切 |
| `AUTHZ_GRPC_URL` | 同一成员名为 `grpc` 的额外端口：`ResolveClaims` 和族的其它 rpc |
| `IAM_URL` | 已安装身份成员的主端口：OIDC discovery、其下的 JWKS 和目录接口 |
| `IAM_GRPC_URL` | 同一成员名为 `grpc` 的额外端口 |
| `IAM_ISSUER` | 每个 token 期望的 `iss`；它是平台的名字，不是 IdP 的，所以是字面量，不是地址 |
| `TENANT_ID` | 每个 token 期望的 `aud`（[0308](../03-contracts-and-data/0308-tenant-is-the-deployment.md)） |

- **每个地址都由 brickKit 算出**，规则与依赖的 `*_ENDPOINT` 相同：`http://<带版本的服务名>:<端口>`，末尾不带 `/`。`brickkit upgrade` 之后跟着成员的版本走；成员被外壳承载时指向外壳；组件以 `mode: local` / `debug` 或 `--focus` 运行时换成本机连得上的地址；Kubernetes 的 `networkPolicy` 自动放行两者之间的连接。SDK 从 `*_GRPC_URL` 去掉 scheme，拨 `host:port`。
- **不做端口算术。** 族的 gRPC 地址就是成员自己声明的、名为 `grpc` 的端口，经它自己的键拿到；从不由 HTTP 地址推出。
- **换成员，每个键改一行** `config/vars.yaml`（外加对成员的 `brickkit add` / `remove`）；不动任何组件的文件。
- **成员不在，键就不在。** 被引用的成员这次不跑时，可选键不注入，组件自行降级；必填键让 `up` 在启动前报错，点名是哪个成员没跑。
- **没有启动顺序，可以成环。** 引用不产生 `depends_on`：授权成员读 `IAM_URL`，身份成员读 `AUTHZ_URL` 和 `AUTHZ_GRPC_URL`；双方都退避重试，直到对方应答。成员也可以引用自己（身份成员把自己的 webhook 地址交给 Casdoor：`$endpoint:infra/iam-casdoor/api/iam/webhooks/casdoor`）。

## 理由

依赖钉的是精确版本，所以每个组件都对 authz 和 iam 建边，两者任何一次发版都会逼所有组件跟着发版。这两个位置都是槽位族：依赖边写死了一个实现（`INFRA_IAM_CASDOOR_ENDPOINT`），换成员就要改每一个组件。组件用公开的公钥在本地验 token，对照本地 bundle 判定权限（[0202](../02-permissions/0202-local-permission-bundle.md)），所以不需要平台安排启动顺序。

在 `config/vars.yaml` 里手写服务名是第一版答案，它的失败方式和任何第二份拷贝一样：成员每发一版名字就变，有一次发版漏改了全部 25 处引用，而 `service-hostname-scan` 门禁只能发现漂移，挡不住漂移。`$endpoint:` 引用由 brickKit 在每次 `up` 时按 `brickkit.yaml` 解析，根本没有可漂移的东西。把 gRPC 端口推成"HTTP 端口 + 1000"是第二条隐藏约定，每个成员都得遵守；每个端口一个键，就只剩成员自己的声明这一个事实。

## 挡下什么

- 把任何 authz 或 IAM 族成员写进 `dependencies.components`，包括从另一个族成员写
- 在 `config/` 或部署文件的 `vars:` 里任何地方，为族成员手写主机名、服务名或端口；地址永远是 `$endpoint:<成员 ID>[:<端口名>][/<路径>]`
- 由族的 HTTP 地址用算术推出 gRPC 地址，用注入的 `*_ENDPOINT` 变量拼任何族地址，或继续保留 `AUTHZ_BUNDLE_URL` 或 `IAM_JWKS_URL`（JWKS 就在 `{IAM_URL}/.well-known/jwks.json`）
- 共享值适用时，仍在某个组件的 `config/<scope>-<name>.yaml` 里写死族地址
- 每个请求都调一次 IAM 组件来校验 token
- 指望平台先启动 authz 或 iam，再启动用到它们的组件
- 在 `$endpoint:` 里写外壳的名字：写成员，外壳承载它期间 brickKit 自会指向外壳
- 为这些调用手工放行 Kubernetes `networkPolicy`：`$endpoint:` 引用已经放行了

## 何时重新讨论

brickKit 去掉 `$endpoint:` 或改变它解析出的东西；或者某个族多了一份需要平台先启动其成员的契约（那它就是依赖，写进 `component.yaml`，族的问题按 [0104](0104-variants-become-slot-families.md) 重新讨论）。

完整分析：[24-config-and-secrets.md，端口契约](../../04-foundations/24-config-and-secrets.md#端口契约)、[20-authorization-provider.md，端口契约](../../04-foundations/20-authorization-provider.md#端口契约)和 [21-identity-provider.md，端口契约](../../04-foundations/21-identity-provider.md#端口契约)。
