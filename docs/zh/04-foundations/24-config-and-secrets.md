[English](../../en/04-foundations/24-config-and-secrets.md) · [中文](24-config-and-secrets.md)

# 配置与密钥

组件怎么拿到配置和密钥，项目里的值怎么写，密钥怎么轮换。读者是要加配置键、要处理口令或私钥，或者被要求接入 Vault、云密钥服务或配置中心的人。

## 范围

- 每个组件对外暴露的配置面，不论它用什么语言；
- brickKit 认识的值形式，以及每种形式在 Docker 和 Kubernetes 上最终落在哪；
- 启动时值怎么解析、怎么校验，单跑和外壳里都一样；
- 密钥来源端口：读密钥、重读密钥、不重启就轮换；
- 开发机上的密钥放在哪。

不在本文：有哪些键、怎么命名（[04-configuration.md](../01-conventions/04-configuration.md)；协议键的完整目录，含类型和默认值，是 `be-protocol` 的 `schemas/config-keys.yaml`，第 P2 章）；各部署目标的具体操作（`brickkit-deploy` 技能）。

## 选择

- **配置只以环境变量的形式到达**，每个都在组件的 `configSchema` 里声明。没有配置服务器，没有运行期配置 API；brickKit 生成好值就退出。
- **值用 brickKit 的形式写**：字面值、`$var:NAME`、`${NAME}`、`file://path`、`{existingSecret: name, key: key}`。
- **解析是严格的**：类型不对的值让启动失败并点名键；不静默回退；模块绝不因配置而 panic。外壳收集所有成员的配置错误，在开始服务前一次报出。
- **SDK 里有一个密钥来源端口**：密钥在用的那一刻经它读取，而不是启动时拷一份。来源有：环境变量（默认）、挂载的文件（变了就重读）、以后的 OpenBao。数据库连接池每建一条新连接都要一次口令，所以口令可以不重启就轮换。
- **Kubernetes**：External Secrets Operator 加 `existingSecret`，零代码。
- **开发机**：一份用 SOPS 加密、提交进 Git 的密钥文件，本地解密成 `.env`，取代单独一份明文 `.env`。

**状态**：已在用：环境变量配置面、brickKit 的值形式、Docker 上 0600 的 env 文件和 Kubernetes Secret。已定（随 3.0.0 统一升级及配套的 SDK 版本）：严格解析、外壳一次报出全部错误、带环境变量与文件两种来源的密钥来源端口、按连接取口令、开发机用 SOPS。以后再做：OpenBao 来源。不重启轮换还要求密钥以文件形式交付，而 brickKit 1.1.0 不生成这种挂载（见**已知限制**）。

## 端口契约

**配置面。**

- 键就是环境变量名，在 `configSchema` 里声明类型、是否必填、默认值，以及是否 `secret: true`（[04-configuration.md](../01-conventions/04-configuration.md#键名)）。
- 组件代码只从 SDK 交给它的运行时读配置，绝不读进程环境（[02-backend.md](../01-conventions/02-backend.md#合并安全)）。
- 外壳里，brickKit 把所有成员的配置打成一个 JSON 值（`BRICKKIT_SERVED_MEMBERS_CONFIG`）传进来；启动器只把每个成员自己的键交给它（[27-shells.md](27-shells.md)）。

**容易弄错的协议键。** 不是完整列表；每个键名和默认值以 `be-protocol` 的 `schemas/config-keys.yaml` 为准。

| 键 | 默认值 | 含义 |
|---|---|---|
| `PG_USER`、`PG_PASSWORD`（secret） | — | 运行期角色：只有 DML，不是属主角色的成员；是服务的登录角色，也是每个事务用 `SET LOCAL ROLE` 切换到的角色。外壳里由外壳的登录角色 `SET LOCAL ROLE` 到各成员的 `PG_USER`（[03-database.md](03-database.md)） |
| `PG_OWNER_USER`、`PG_OWNER_PASSWORD`（secret） | — | 属主角色：`LOGIN`，拥有表，执行迁移和平台迁移；绝不写成字面量，运行中的服务从不使用。限制：brickKit 给迁移容器的环境与服务相同，所以运行中的进程也会收到这两个键，SDK 不理会它们；等 brickKit FR06-013（只给迁移步骤的环境变量覆盖）落地后才改变 |
| `S3_PUBLIC_URL` | `S3_URL` | 浏览器使用的地址；预签名 URL 按它签名（[22-object-storage.md](22-object-storage.md)） |
| `DEFAULT_LOCALE` | `zh-CN` | 部署的默认语言（BCP 47），共享：错误体的 `title` 和 `detail`，以及服务端文本的回退语言（[26-i18n-data.md](26-i18n-data.md)） |
| `AUTHZ_URL`、`IAM_URL` | — | 已安装的授权 / 身份成员的基础 URL，用成员自己的服务名，共享，写在 `config/vars.yaml`，从不是依赖边。该族的 gRPC 端口按 `be-protocol` P2 的规则从它的 `*_URL` 推出 |
| `BOOTSTRAP_ADMIN_LOGIN` | — | 第一位管理员在 IdP 的登录名或电子邮箱，共享；在此人第一次登录时绑定到平台 `sub`，因为平台 `sub` 事先无法知道。不存在 `BOOTSTRAP_ADMIN_SUB` |
| `EVENTS_MAX_DELIVER` | `8` | SDK 一侧的死信阈值：消息的 `NumDelivered` 超过它时，SDK 写入死信消息并终止原消息；服务端的 `MaxDeliver` 是 `-1`（[12-event-bus.md](12-event-bus.md)） |
| `EVENTS_BACKOFF` | `1s,10s,1m,5m,15m,30m,1h` | SDK 的 `NakWithDelay` 延迟序列；消费者没有服务端 `BackOff` |

**值形式**，写在 `config/vars.yaml`、`config/<scope>-<name>.yaml` 或部署文件的 `vars:` 里：

| 写法 | 含义 | Docker / Podman | Kubernetes |
|---|---|---|---|
| 字面值 | 值本身 | `compose.yaml` 的 `environment` | `env.value` |
| `$var:NAME` | `config/vars.yaml` 或部署文件 `vars:` 里的共享值 `NAME` | 写成解析后的值 | 写成解析后的值 |
| `${NAME}` | 先取进程环境，再取 `.env`；未定义时生成失败（`${NAME:-}` 允许为空） | 由 compose 在启动时展开；`secret: true` 的项进 `.brickkit/generated/env/<service>.env`（权限 0600） | 生成时展开；`secret: true` 的项进生成的 Secret，用 `secretKeyRef` 引用 |
| `file://.secrets/x` | 文件内容，**在生成部署文件时读入并内联** | 进 0600 的 env 文件 | 进生成的 Secret |
| `{existingSecret: name, key: key}` | 由别处管理的 Kubernetes Secret | 不注入（给出警告） | 直接 `secretKeyRef` 到它；brickKit 从不读它 |

**解析规则**，每个 SDK 都一样：

- 整数、布尔、时长解析失败时，启动失败并点名键；有值但非法时绝不回退到默认值。
- 缺必填键时启动失败并点名键。
- 外壳里收集所有成员的错误一起打印，外壳不启动；模块返回错误，绝不退出进程。

**密钥来源。**

- 密钥在用的时候经来源读取，来源回答当前值或一个错误。
- **环境变量来源**（默认）：环境变量的值。进程运行期间它不会变。
- **文件来源**（已定）：密钥的配置值是运行期文件引用 `@file:/run/secrets/<name>` 时，来源读这个文件，文件修改时间变了就重读。它不是 brickKit 的 `file://`——后者在生成时就内联了；`@file:` 指的是挂进运行中容器的文件（Kubernetes Secret 卷、OpenBao Agent 写出的文件、compose secret）。
- **OpenBao 来源**（以后再做）：AppRole 或 Kubernetes 认证、租约续期，放在同一份契约后面。
- 数据库连接池每建一条新连接都经来源读 `PG_PASSWORD`。轮换：`ALTER ROLE … PASSWORD` → 更新密钥 → 新连接用新口令；旧连接到 `PG_CONN_MAX_LIFETIME`（默认 30 分钟，见 [03-database.md](03-database.md)）自然退役。
- **token 签名私钥**靠发布两把钥轮换：iam 成员用当前钥签名，JWKS 里同时发布当前钥和上一把钥（`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM`），切换前签的 token 仍能验过（[21-identity-provider.md](21-identity-provider.md)）。

**开发机**（已定）：提交一份用 SOPS 和 age 密钥加密的 `secrets.enc.yaml`；每个开发者用自己的密钥把它解密成 `.env`。密钥的值绝不打印、不记日志、不贴进对话。

## 备选方案

| 方案 | 是什么 | 许可证 | 对本项目 |
|---|---|---|---|
| 环境变量 + `.env`（已在用） | 最简单 | — | 仍是默认配置面 |
| Kubernetes Secret + External Secrets Operator | 把 Vault、OpenBao 或云 KMS 同步成 Kubernetes Secret | Apache-2.0 | 推荐的 Kubernetes 路径，配 `existingSecret`，零代码 |
| HashiCorp Vault | 动态数据库凭据、租约 | 2023 年起 BUSL | 许可证有风险 |
| OpenBao（Linux 基金会的 Vault 分支） | 与 Vault 的 API 兼容 | MPL-2.0 | 直接接入的来源适配器的首选目标 |
| SOPS（CNCF） | 加密文件提交进 Git | MPL-2.0 | 在开发机上取代明文 `.env` |
| 云密钥服务 / KMS | 托管 | 商业 | 经 External Secrets Operator 接入 |
| 配置中心（Nacos、Apollo、Consul KV） | 运行期提供动态配置 | — | 不选：配置服务器是 brickKit 设计排除的运行期依赖 |

## 为什么选它

- 遵循 brickKit：CLI 生成部署文件就退出；没有配置服务器要保活，启动时也不依赖它。
- 每种语言同一个配置面：环境变量是可移植性最好的契约。
- 严格解析把手误变成一个点名键的启动错误，而不是组件悄悄用默认值跑着。
- 在用的那一刻才读的来源，让轮换不必重启进程，组件代码也不必知道密钥从哪来。

## 为什么不选其他

- **配置中心**：每个组件的运行期依赖，`config/` 之外的第二个事实源，"跑着的"不再等于"提交的"。
- **组件直接调 Vault**：每个组件都得学一个厂商 API，而且 Vault 的许可证变了；OpenBao 放在来源端口后面能得到同样的效果，没有这些问题。
- **只有明文 `.env`**：密钥曾从它泄露进日志和对话；加密文件放进 Git，既能共享又不暴露。

## 什么时候换

- 客户强制使用某个密钥平台：Kubernetes 上用 External Secrets Operator 加 `existingSecret`（什么都不改）；别的环境在密钥来源端口后面为该平台加一个适配器。
- 客户要求不重启轮换：用文件来源，密钥以文件形式挂载。

## 怎么换

1. Kubernetes 加 External Secrets Operator：在 `config/<scope>-<name>.yaml` 里把该项写成 `{existingSecret: <name>, key: <key>}`。只有声明了 `secret: true` 的项接受这种写法。
2. 文件来源：把密钥的值设为 `@file:/run/secrets/<name>`，并确保文件已挂进容器。
3. 新来源（OpenBao 或别的平台）：在每个官方 SDK 里实现来源契约，跑密钥一致性套件，再在配置里选用；组件代码不改。

## 一致性测试

套件 `tools/be-acceptance/conformance/secret/`（已定）：请求持续进行时，经文件来源轮换数据库口令，失败请求为零。

每个官方 SDK 里的测试，先写红：

- 有值但非法的整数让启动失败并点名键；
- 有两个成员配置错误的外壳一次报出两个错误，且不 panic；
- 密钥文件变了以后，来源返回新值；
- 口令轮换后新连接成功，旧连接到最大寿命时退役。

## 相关决策

- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：共享连接键在 `config/vars.yaml` 里只写一次。
- [0107 授权与身份经共享变量访问，从不经依赖](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：共享地址就是配置。
- [0109 规则写在语言中立的组件协议里，由黑盒套件检查](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md)：配置键和严格解析是组件协议的一部分。
- 计划新增：无。"没有配置服务器"是 brickKit 自己的设计原则，记在根目录 `AGENTS.md` 里。

## 已知限制

- 能查看容器的人都看得到环境变量；Docker 上的密钥放在宿主机上的 0600 文件里。
- brickKit 1.1.0 只以环境变量的形式交付密钥（Docker 的 env 文件、Kubernetes 的 `secretKeyRef`），不把它们挂载成文件。在它支持之前，文件来源需要一个 brickKit 生成文件之外的挂载；标准部署上的轮换就是：改值、重新生成、重启。计划向 brickKit 提一个功能请求。
- `file://` 只在生成时读一次：改了文件，在重新生成并重启组件之前什么都不会变。
- `existingSecret` 只存在于 Kubernetes。
- 外壳成员的配置作为一个 JSON 值走密钥路径；一个成员的密钥和别的成员的放在同一个值里。
