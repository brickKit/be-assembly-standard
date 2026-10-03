[English](../../en/04-foundations/21-identity-provider.md) · [中文](21-identity-provider.md)

# 身份提供方

谁来认证一个人，平台签发什么样的 token，用户 id 归谁，以及背后的身份提供方怎么替换。读者是要动登录、token 验签、用户目录，或者打算换掉 Casdoor 的人。

## 范围

- 浏览器、身份提供方（IdP）与平台之间的登录流程；
- 应用 token：它的 claims、签名公钥（JWKS）、每个 SDK 里的验签规则；
- 平台自有的用户 id（`sub`）及其与 IdP 账号的链接；
- 目录事件（用户建立、更新、停用、删除）与用户查询；
- IAM 槽位族、它的族契约和一致性套件；
- 给服务账号和委托 token 预留的形状。

不在本文：一个人被认出之后能做什么（[20-authorization-provider.md](20-authorization-provider.md)）；租户（`tenant_id`、`aud`、每个客户一套部署：[07-tenancy.md](07-tenancy.md)）。

## 选择

- **IdP 只负责认证。** 已安装的 IAM 成员拿 IdP 的 ID token 换**平台自己的应用 token**，每个组件用发布的公钥在本地验签。
- **`sub` 归平台所有。** token 里的 `sub` 是平台用户 id（UUIDv7）。IdP 的主体标识只存在成员的链接表里，所以换 IdP 绝不会改写任何 `owner_id`、角色分配或审计记录。
- **前端与 IdP 之间只用标准**：OIDC discovery、带 PKCE 的授权码流程、RFC 8693 形状的换 token。前端里、契约字段里都不出现厂商路径。
- **一个槽位族**，契约 `infra.iam.v1` 放在独立仓库 `contract-infra-iam`，套件 `iamconf`。成员依次是：`infra/iam-casdoor`（默认）、`infra/iam-keycloak`（第二实现，阶段 06 内建）、通用 OIDC + SCIM 成员（第三实现）。
- **任何组件都不依赖某个成员。** 组件读 `IAM_URL`，在它下面取 JWKS（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）；IAM 成员自己也只经 `AUTHZ_URL` 和 `AUTHZ_GRPC_URL` 访问 authz，不建依赖边。

**状态**：已在用：`infra/iam-casdoor` 2.0.x 拿 Casdoor 的 ID token（字段 `casdoor_id_token`）换一个 RS256 token，带 `sub`（就是 Casdoor 的主体标识）、`roles`、`dept_path`、`org_id`，TTL 600 秒，refresh 轮换，JWKS 在 `/.well-known/jwks.json`，Casdoor 的 webhook 桥接成用户事件。已定（随 3.0.0 统一升级）：本文其余全部内容。access token 现在还不带 `iss`、`aud`、`jti`、`typ`，refresh token 能当 access token 通过验签；补上 `typ: access`、拒收 `typ: refresh` 是第一个要修的。

## 端口契约

**登录配置。** `GET /api/iam/login-config`（公开）→ `{issuer, discovery_url, client_id, scopes, pkce: "S256", end_session_supported}`。前端从 `discovery_url` 读 IdP 的 `/.well-known/openid-configuration`，从里面拿授权端点和 token 端点。`GET /api/tenant/features`（公开）只带登录页在登录前需要的内容：`contract`、`tenant_id`、`capabilities`、`default_locale`、`locales`。

**换 token。** `POST /api/iam/token`，表单编码：

| 字段 | 值 |
|---|---|
| `grant_type` | `urn:ietf:params:oauth:grant-type:token-exchange` |
| `subject_token` | IdP 的 ID token |
| `subject_token_type` | `urn:ietf:params:oauth:token-type:id_token` |
| `audience` | 可选 |

回答带 `access_token`、`issued_token_type`、`token_type`、`expires_in`、`refresh_token`、`refresh_expires_in`。在 06c 前端改用 token exchange 之前，Casdoor 成员也接受字段 `casdoor_id_token`；改完之后删除。`POST /api/iam/token/refresh` 轮换 refresh token（旧的立即失效）；`POST /api/iam/logout` 作废它。

**token 错误。** 这几条路径上的每个失败都是 problem+json（[15](15-user-api-and-errors.md#错误体)），reason 属于 domain `infra/iam`（族的 ID，不管装的是哪个成员），或是保留的 `be` reason；`metadata.oauth_error` 带 RFC 6749 §5.2 的错误码（`invalid_grant`、`invalid_request` 等），供懂 OAuth 的客户端映射。没有顶层的 `error` 成员。

**应用 token 的 claims：**

| claim | 含义 |
|---|---|
| `iss` | 平台签发者，共享键 `IAM_ISSUER`：一个稳定的名字 `urn:be:<TENANT_ID>:iam`，不是地址；换成员时不变 |
| `aud` | 本部署，共享键 `TENANT_ID` |
| `sub` | 平台用户 id（UUIDv7）；服务账号是 `svc:<id>`（预留） |
| `typ` | `access` 或 `refresh` |
| `iat`、`nbf`、`exp`、`jti` | 标准字段；access TTL 600 秒，refresh 7 天 |
| `tenant_id` | 租户 / 默认法人；`org_id` 弃用 |
| `roles`、`dept_path` | 登录和刷新时经授权提供方的 `ResolveClaims` 解析得到；用户没有部门时**省略** `dept_path`，绝不写成 `""` 或 `"/"` |
| `act` | `{sub, kind: user|agent|svc}`，实际操作者，可嵌套（RFC 8693 §4.1）；`agent` 是预留值 |
| `ceil`、`dg` | 天花板 profile 码和委托授予 id（[20-authorization-provider.md](20-authorization-provider.md)） |
| `azp` | 客户端（PC、移动端） |
| `locale` | 用户的语言，供服务端出文字用 |

**签名公钥。** `{IAM_URL}/.well-known/jwks.json` 上的 JWKS 发布一到三把钥：当前钥、轮换期间的上一把钥，以及可选的、提前发布的下一把钥；每把钥都有 `kid` 和 `alg`。私钥是密钥文件 `APP_TOKEN_SIGNING_KEY_FILE` 和 `APP_TOKEN_NEXT_SIGNING_KEY_FILE`，不重启就会重读；成员把签过名的每把公钥记在自己的 schema 里，所以重叠期跨重启、跨副本都成立（[24](24-config-and-secrets.md#端口契约)）。

**验签规则，每个 SDK、每种语言都一样：**

- `alg` 取自 JWKS 里那把钥，且必须是 `RS256`、`ES256`、`EdDSA` 之一；token 头不能自己选。
- `kid` 必填。没见过的 `kid` 先重新拉一次 JWKS（限频），仍找不到就失败。
- `iss` 必须等于 `IAM_ISSUER`；`aud` 必须包含 `TENANT_ID`；检查 `exp` 和 `nbf`。
- `typ` 必须是 `access`；`refresh` 和缺失 `typ` 的一律拒收。
- token 的 `iat` 早于 bundle 里该 `sub` 的 `stale_since` 时答 `401`，reason 为 `TOKEN_STALE`，并带 `WWW-Authenticate: Bearer error="token_stale"`，前端静默刷新。

**平台 `sub` 与身份链接。** 成员维护 `identity_links(idp, idp_issuer, idp_sub, user_id)`，每个 IdP 账号一行。一个陌生 IdP 账号首次登录时建一个平台用户。默认只按 `(idp_issuer, idp_sub)` 精确链接到已有用户；按 e-mail 自动链接是一个有安全风险的可选项。族契约定义链接的 NDJSON 导出格式，新成员导入后每个 `sub` 都保持不变。

**首个管理员。** 平台 `sub` 要到一个人首次登录之后才存在，所以首个管理员用 `BOOTSTRAP_ADMIN_LOGIN` 指定：IdP 的登录名，或一个已验证的 e-mail 地址。换 token 时成员按不区分大小写的方式匹配它，每套部署至多绑定一次，绑定到这个人的平台 `sub`，并发布带 `bootstrap_admin: true` 的目录事件；授权成员收到这个事件后授予它的管理员角色。`BOOTSTRAP_ADMIN_LOGIN` 取代原来的 `BOOTSTRAP_ADMIN_SUB`。

**目录事件。** `infra.iam.user.created.v1`、`.updated.v1`、`.disabled.v1`、`.deleted.v1`（deleted 是新增的）。payload 至少含 `sub`、`display_name`、`email`、`phone`、`locale`、`im_accounts`、`status`。成员怎么得知变更是它自己的事：Casdoor 用 webhook，Keycloak 轮询 admin events，通用成员用 SCIM 2.0 入站（`/scim/v2/Users`、`/scim/v2/Groups`）。

**系统 RPC**（`infra.iam.v1.IamProvider`，经 `IAM_GRPC_URL` 访问；没有这个键时这些读取降级）：`BatchGetUsers`（sub 列表 → 展示信息）和 `ListUsers`（core）；`ListDepartments` 和 `ListMemberships`（能力 `directory_departments`）。没有 `GetTenantFeatures`：已安装的组件（今天的 `enabled_components`）、键和能力并进授权提供方要登录的 `GET /api/me/access`（[20-authorization-provider.md](20-authorization-provider.md)）；公开的 `/api/tenant/features` 只保留登录页的字段。

**能力**，登录页按成员声明的能力降级：`password_login`、`social_cn`（钉钉、企业微信、飞书）、`ldap`、`saml`、`scim_inbound`、`mfa`、`token_exchange_delegation`、`service_accounts`。

**预留、不开发**：服务账号（`sub: svc:<id>`，走 client credentials，是系统面的扩展点，见 [14-system-rpc.md](14-system-rpc.md)）；用于委托的换 token（`act`、`ceil`、`dg`），不做 agent 分支。

**配置。** `config/vars.yaml` 里的共享键（已定）：`IAM_URL: $endpoint:infra/iam-casdoor`（REST 基础地址；JWKS 在 `{IAM_URL}/.well-known/jwks.json`）、`IAM_GRPC_URL: $endpoint:infra/iam-casdoor:grpc`（名为 `grpc` 的端口）、`IAM_ISSUER`（`urn:be:<TENANT_ID>:iam`）、`TENANT_ID`、`BOOTSTRAP_ADMIN_LOGIN`。`IAM_JWKS_URL` 退役：它只是同一个成员的第二个地址。成员把自己的 webhook 地址以 `$endpoint:infra/iam-casdoor/api/iam/webhooks/casdoor` 交给 Casdoor，这是对自己的引用。服务器元数据（RFC 8414 的形状）在 `{IAM_URL}/.well-known/oauth-authorization-server`，相对 `IAM_URL` 而不是相对签发者，因为签发者是名字而不是 URL。IdP 服务本身（Casdoor、Keycloak）是 `make up` 启动的基础设施，不是组件（[0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)），它用自己的角色登录自己的 schema，绝不用 `postgres`。

## 备选方案

| IdP | 语言、资源 | 许可证 | 标准 | 国内生态 | 适合 |
|---|---|---|---|---|---|
| **Casdoor**（默认成员） | Go，轻 | Apache-2.0 | OIDC、OAuth 2、SAML、LDAP；webhook | 内置钉钉、企业微信、飞书、微信登录 | 国内中小客户 |
| **Keycloak**（第二成员） | Java，约 0.5–1 GB 内存 | Apache-2.0，CNCF | 最全：OIDC、SAML、LDAP / AD 联邦、标准 token exchange（26.2 起） | 社区插件 | 大型企业、已有 AD 的客户 |
| Zitadel | Go | v3 起 AGPL-3.0 | OIDC、SAML、多租户组织 | 弱 | 要评估许可证 |
| Authentik | Python | 核心 MIT | OIDC、SAML、LDAP 出口、SCIM 出口 | 弱 | 中型、偏运维友好 |
| Ory（Kratos + Hydra + Keto） | Go，多个服务 | Apache-2.0 | 无头：登录界面要自己做 | 无 | 完全自定义登录 |
| Logto | TypeScript | MPL-2.0 | OIDC，组织是一等概念 | 弱 | SaaS 开发者体验 |
| 客户自有 IdP（Entra ID、Okta、钉钉统一身份） | — | — | OIDC + SCIM 2.0 | 钉钉支持 OIDC | 企业客户，经通用成员接入 |

另外权衡过两种架构上的备选：组件直接验 IdP 的 token；把 IdP 的主体标识当平台 `sub`。

## 为什么选它

- 换 IdP 不碰业务数据：`sub` 归平台，token 形状归族契约。
- 国内社交登录靠 Casdoor；企业联邦靠 Keycloak；客户自有 IdP 靠通用成员。一份契约，三个真实场景。
- 只用标准（discovery、PKCE、RFC 8693、SCIM），前端和每个组件只写一次。
- 按 JWKS 本地验签，IAM 不在请求路径上（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）。

## 为什么不选其他

- **组件直接验 IdP 的 token**：角色和部门 claims 就要依赖各家 IdP 的 claim 格式，每个组件都会跟着 IdP 变。
- **IdP 的主体标识当 `sub`**：换 IdP 就要改写每个 `owner_id`、每条分配和审计记录。
- **Zitadel**：v3 起 AGPL，而且它能证明的 Keycloak 已经证明了。
- **Authentik、Logto**：国内生态弱，证明不了 Keycloak 之外的东西。**Ory**：无头，登录界面就成了我们要做、要维护的东西。

## 什么时候换

| 成员 | 什么时候选 |
|---|---|
| `infra/iam-casdoor` | 默认：中小客户、国内社交登录、单机 |
| `infra/iam-keycloak` | 要联邦 Active Directory 或 LDAP、要 SAML、大型企业；单机上要给 JVM 的内存留出预算 |
| 通用 OIDC + SCIM 成员 | 客户已有 Entra ID、Okta 或钉钉统一身份，并用 SCIM 推送用户 |

## 怎么换

1. 从旧成员导出身份链接（NDJSON），导入新成员，把新 IdP 的主体标识链接到已有的平台 `sub`。
2. `brickkit add` 新成员、`brickkit remove` 旧成员；没有组件要改依赖。
3. 改掉 `config/vars.yaml` 里 `IAM_URL` 和 `IAM_GRPC_URL` 中的成员 ID（`$endpoint:infra/iam-keycloak`、`$endpoint:infra/iam-keycloak:grpc`）。`IAM_ISSUER` 标识的是平台，不是 IdP，保持不变。
4. 用户重新登录：旧成员的钥从 JWKS 里消失后，它签的 token 就验不过了。
5. 对新成员跑 `iamconf`。前端不改；它只读 discovery。

今天平台 `sub` 还不存在，换一次意味着重签 token，再对种子和测试数据做一次 `db-reset`；数据越多代价越大，所以平台 `sub` 先落地。

## 一致性测试

套件 `tools/be-acceptance/conformance/iam/`（`iamconf`）。套件自带一个签 ID token 的测试 OIDC 提供方；被测成员配置成联邦到它，或者对一个真实的 IdP 容器跑。

- discovery 字段齐全；换 token 接受 RFC 8693 形状；
- 签出的 token 带 `iss`、`aud`、`jti`、`typ`、`tenant_id`；
- refresh token 当 access token 用被拒；轮换后旧的 refresh token 立即失效；
- 钥轮换期间，当前钥和上一把钥签的 token 都能验过；
- 同一个 IdP 账号登录两次拿到同一个 `sub`；身份链接导出再导入后每个 `sub` 不变；
- 用户停用事件在有界时间内发出，下一次登录被拒；
- 没声明的能力明确降级。

SDK 侧，每个官方 SDK：拒收 `typ: refresh`；执行 `alg` 白名单；校验 `iss` 和 `aud`。前端（FE-1）：登录流程对一份非 Casdoor 的 discovery 文档能走通。

## 相关决策

- [0203 token 只承载身份，`sub` 归平台所有](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md)：token 的 claim 和平台自有的 `sub`。
- [0308 租户就是部署](../02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md)：租户就是部署：`aud` 是 `TENANT_ID`，`tenant_id` 在线上预留。
- [0107 族成员的地址是共享变量里的 `$endpoint:` 引用](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：`IAM_URL`、`IAM_GRPC_URL`、`IAM_ISSUER` 和 `TENANT_ID` 是共享变量；iam → authz 依赖边删除。
- [0210 委托与扮演](../02-decisions/02-permissions/0210-delegation-and-impersonation.md)：委托在 token 一侧的形状，代理人只留位子。
- [0104 槽位族需要多种合理实现，而且没有依赖边](../02-decisions/01-architecture/0104-variants-become-slot-families.md)：`slot:iam`。
- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：IdP 服务。
- [0303 测试账号不写进迁移](../02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md)：首个管理员来自 `BOOTSTRAP_ADMIN_LOGIN`，绝不来自迁移或种子。

## 已知限制

- 撤销一个人的权限经 bundle 的 `stale_since`（约 15 秒）或 token 过期（600 秒）生效，不是即时的。
- 通用 OIDC + SCIM 成员还不存在；在那之前，客户自有 IdP 经 Keycloak 联邦接入。
- 国密（SM2 签名）只是列出的能力项，有客户真正要求时再做。
- Keycloak 是 JVM：单机上它比 Casdoor 明显多占内存。
