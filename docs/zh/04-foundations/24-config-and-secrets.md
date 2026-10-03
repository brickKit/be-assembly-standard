[English](../../en/04-foundations/24-config-and-secrets.md) · [中文](24-config-and-secrets.md)

# 配置与密钥

组件怎么拿到配置和密钥，项目里的值怎么写，密钥怎么轮换。读者是要加配置键、要处理口令或私钥，或者被要求接入 Vault、云密钥服务或配置中心的人。

## 范围

- 每个组件对外暴露的配置面，不论它用什么语言；
- brickKit 认识的值形式（包括表示另一个组件地址的 `$endpoint:`），以及每种形式在 Docker 和 Kubernetes 上最终落在哪；
- 启动时值怎么解析、怎么校验，单跑和外壳里都一样；
- 密钥：以文件交付，在用的那一刻读，变了就重读，不重启就轮换；
- 开发机上的密钥放在哪。

不在本文：有哪些键、怎么命名（[04-configuration.md](../01-conventions/04-configuration.md)；协议键的完整目录，含类型和默认值，是 `be-protocol` 的 `schemas/config-keys.yaml`，第 P2 章）；各部署目标的具体操作（`brickkit-deploy` 技能）。

## 选择

- **配置只经环境变量到达**，每个都在组件的 `configSchema` 里声明。没有配置服务器，没有运行期配置 API；brickKit 生成好值就退出。
- **密钥的值从不放进环境变量。** 每个声明了 `secret: true` 的键，不论是协议键还是组件自己的键，都同时声明 `mount: file`、键名以 `_FILE` 结尾，其他键都不以 `_FILE` 结尾（be-protocol P2.12）（`PG_PASSWORD_FILE`、`PG_OWNER_PASSWORD_FILE`、`S3_SECRET_ACCESS_KEY_FILE`、`APP_TOKEN_SIGNING_KEY_FILE`）：brickKit 把值写进一个挂进容器的文件，变量里放的是这个文件的路径。
- **SDK 在用的那一刻读密钥文件，文件变了就重读**（比较修改时间和大小，两次比较最多相隔 30 s）。数据库连接池每建一条新连接都读一次口令，所以口令不重启就能轮换；签名私钥靠 JWKS 里新旧两把钥重叠来轮换。
- **值用 brickKit 的形式写**：字面值、`$var:NAME`、`${NAME}`、`file://path`、`$endpoint:<组件 ID>[:<端口>][/<路径>]`、`{existingSecret: name, key: key}`。不是声明依赖的另一个组件（槽位族成员）的地址，一律写 `$endpoint:`，从不手写（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）。
- **每个 `configSchema` 里的协议键那一段是生成的。** be-ops 按 `be-protocol` 的 `schemas/config-keys.yaml`，把组件的 profile 需要的协议键连同目录里的类型、默认值、`secret` 和 `mount` 标记写进去；这一段不是最新时门禁失败。brickKit 不做 `configSchema` 片段引用（FR06-014）：已发布的 `component.yaml` 必须自己说完自己，所以拷贝在发版前由生成器做，而不是读取时去引用。
- **解析是严格的**：类型不对的值让启动失败并点名键；不静默回退；模块绝不因配置而 panic。外壳收集所有成员的配置错误，在开始服务前一次报出。
- **Kubernetes**：External Secrets Operator 加 `existingSecret`，和别的密钥一样挂成文件；零代码。
- **开发机**：一份用 SOPS 加密、提交进 Git 的密钥文件，本地解密成 `.env`，取代单独一份明文 `.env`。

**状态**：已在用：环境变量配置面、brickKit 的值形式、Docker 上 0600 的 env 文件和 Kubernetes Secret。brickKit 1.2 加了 `$endpoint:`，1.3 加了以文件交付的密钥（`mount: file`），正是本设计需要平台提供的两样机制。已定（随 3.0.0 统一升级及配套的 SDK 版本）：每个密钥都是 `_FILE` 键、三门 SDK 都重读文件、生成的协议键段、族地址用 `$endpoint:` 引用、严格解析、外壳一次报出全部错误、开发机用 SOPS。以后再做：OpenBao 来源。

## 端口契约

**配置面。**

- 键就是环境变量名，在 `configSchema` 里声明类型、是否必填、默认值、是否 `secret: true`，密钥还要声明 `mount: file`（[04-configuration.md](../01-conventions/04-configuration.md#键名)）。
- 组件代码只从 SDK 交给它的运行时读配置，绝不读进程环境（[02-backend.md](../01-conventions/02-backend.md#合并安全)）。
- 外壳里，brickKit 把所有成员的配置打成一个 JSON 值（`BRICKKIT_SERVED_MEMBERS_CONFIG`）传进来；启动器只把每个成员自己的键交给它（[27-shells.md](27-shells.md)）。成员的 `mount: file` 项不进 JSON：JSON 里是路径，文件挂进外壳的容器，路径和成员单跑时一模一样。

**容易弄错的协议键。** 不是完整列表；每个键名和默认值以 `be-protocol` 的 `schemas/config-keys.yaml` 为准。

| 键 | 默认值 | 含义 |
|---|---|---|
| `PG_USER`、`PG_PASSWORD_FILE`（密钥，文件） | — | 运行期角色：只有 DML，不是属主角色的成员；是服务的登录角色，也是每个事务用 `SET LOCAL ROLE` 切换到的角色。外壳里由外壳的登录角色 `SET LOCAL ROLE` 到各成员的 `PG_USER`（[03-database.md](03-database.md)） |
| `PG_OWNER_USER`、`PG_OWNER_PASSWORD_FILE`（密钥，文件） | — | 属主角色：`LOGIN`，拥有表，执行迁移和平台迁移；绝不写成字面量，运行中的服务从不使用。brickKit 给迁移容器的环境和挂载与服务完全相同（FR06-013"只给迁移的覆盖"被有意不做），所以运行中的容器里也有属主的口令文件；SDK 运行期从不读它 |
| `PG_MIGRATION_HOST`、`PG_MIGRATION_PORT` | `PG_HOST`、`PG_PORT` | `PG_HOST` 是 transaction 模式的 pooler 时，迁移改连这里，直连 PostgreSQL。迁移需要另一条连接时，这正是 brickKit 推荐的做法：由组件声明自己的键（[08-schema-evolution.md](08-schema-evolution.md#迁移入口)） |
| `AUTHZ_URL`、`AUTHZ_GRPC_URL`、`IAM_URL`、`IAM_GRPC_URL` | — | 已安装的授权 / 身份成员的主端口和名为 `grpc` 的端口，在 `config/vars.yaml` 里以 `$endpoint:` 引用写一次（`$endpoint:infra/authz:grpc`），从不是依赖边，也从不手写地址。值是 `http://host:port`，末尾不带 `/`；SDK 把 `*_GRPC_URL` 当 `host:port` 拨号（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)） |
| `S3_PUBLIC_URL` | `S3_URL` | 浏览器使用的地址；预签名 URL 按它签名（[22-object-storage.md](22-object-storage.md)） |
| `DEFAULT_LOCALE` | `zh-CN` | 部署的默认语言（BCP 47），共享：错误体的 `title` 和 `detail`，以及服务端文本的回退语言（[26-i18n-data.md](26-i18n-data.md)） |
| `BOOTSTRAP_ADMIN_LOGIN` | — | 第一位管理员在 IdP 的登录名或电子邮箱，共享；在此人第一次登录时绑定到平台 `sub`，因为平台 `sub` 事先无法知道。不存在 `BOOTSTRAP_ADMIN_SUB` |
| `EVENTS_MAX_DELIVER` | `8` | SDK 一侧的死信阈值：消息的 `NumDelivered` 超过它时，SDK 写入死信消息并终止原消息；服务端的 `MaxDeliver` 是 `-1`（[12-event-bus.md](12-event-bus.md)） |
| `EVENTS_BACKOFF` | `1s,10s,1m,5m,15m,30m,1h` | SDK 的 `NakWithDelay` 延迟序列；消费者没有服务端 `BackOff` |
| `SHUTDOWN_GRACE` | `25s` | 收到 `SIGTERM` 后留给在途工作的时间；比平台的停机宽限期至少小 5 s，后者由组件在 `component.yaml` 的 `deployment.stopGracePeriodSeconds` 里声明（默认 `30`）（[27-shells.md](27-shells.md#端口契约)） |

**值形式**，写在 `config/vars.yaml`、`config/<scope>-<name>.yaml` 或部署文件的 `vars:` 里：

| 写法 | 含义 | Docker / Podman | Kubernetes |
|---|---|---|---|
| 字面值 | 值本身 | `compose.yaml` 的 `environment` | `env.value` |
| `$var:NAME` | `config/vars.yaml` 或部署文件 `vars:` 里的共享值 `NAME` | 写成解析后的值 | 写成解析后的值 |
| `${NAME}` | 先取进程环境，再取 `.env`；未定义时生成失败（`${NAME:-}` 允许为空） | 由 compose 在启动时展开；没有 `mount: file` 的 `secret: true` 项进 `.brickkit/generated/env/<service>.env`（权限 0600） | 生成时展开；`secret: true` 的项进生成的 Secret |
| `file://.secrets/x` | 文件内容，**在生成部署文件时读入**；相对路径从项目根算起，也可以写绝对路径（`file:///etc/…`） | 内联进 env 文件，或写进挂载的密钥文件 | 进生成的 Secret |
| `$endpoint:<ID>[@<版本>][:<端口>][/<路径>]` | 另一个组件的地址，`http://<带版本的服务名>:<端口>` 加路径；与 `*_ENDPOINT` 同一规则算出，跟着升级、外壳和本机运行走；不产生启动顺序，可以成环；被引用的组件这次不跑时不存在 | 写成解析后的值 | 写成解析后的值；`networkPolicy` 放行这条连接 |
| `{existingSecret: name, key: key}` | 由别处管理的 Kubernetes Secret | 不注入（给出警告） | `mount: file` 的项挂成文件，和生成的放在同一目录；其余用 `secretKeyRef` |

**以文件交付的密钥**（`secret: true` 加 `mount: file`，所有密钥都是）：

| | Docker / Podman | Kubernetes | `mode: local` / `debug` |
|---|---|---|---|
| 文件在哪 | `/run/brickkit/secrets/<带版本的服务名>/<KEY>`，来自 `.brickkit/generated/secrets/<service>/` 的只读目录挂载 | 同一路径，生成的 Secret（以及 `existingSecret`）的投射卷 | 文件在宿主机上的绝对路径 |
| 变量里是什么 | 路径 | 路径 | 路径 |
| 值变了之后 | `up` 改写文件；容器不重建 | `up` 更新 Secret；kubelet 同步文件，通常一分钟内；不重启，文件项也不触发 `brickkit.io/secret-digest` 滚动 | `up` 改写文件 |

- 文件内容逐字节就是值：不加引号、不转义、不补换行；二进制也可以。
- 迁移容器挂载主容器挂载的一切。
- `up --dry-run` 不写任何密钥文件：写进去就等于部署了。
- 宿主机上 `.brickkit/generated/secrets/` 是 0700；其下的文件"其他人可读"，因为容器里的进程通常既不是 root，也不是宿主机上的这个用户。

**解析规则**，每个 SDK 都一样：

- 整数、布尔、时长解析失败时，启动失败并点名键；有值但非法时绝不回退到默认值。
- 缺必填键时启动失败并点名键；`_FILE` 键的文件在启动时不存在或读不了，也一样。
- 外壳里收集所有成员的错误一起打印，外壳不启动；模块返回错误，绝不退出进程。

**运行期的密钥文件。**

- 密钥在用的时候经 SDK 读取，SDK 回答当前内容或一个错误；组件代码从不自己打开这个文件。
- SDK 记住内容，文件的修改时间或大小变了就重读，两次比较最多相隔 30 s（文件系统监视可以更早发现）；它从不为此重启，每次变化记一条点名键的 INFO。文本密钥恰好去掉一个结尾换行；组件自己的二进制密钥逐字节交出。变化之后读失败时保留上一个有效值，记一条点名键（从不含值）的 ERROR，并计入 `be_secret_reload_failures_total`。
- **数据库凭据**：连接池每建一条新连接都读 `PG_PASSWORD_FILE`。轮换：`ALTER ROLE … PASSWORD` → 改 `config/` 里的值 → `up` → 新连接用新口令；旧连接到 `PG_CONN_MAX_LIFETIME`（默认 30 分钟，见 [03-database.md](03-database.md)）自然退役。
- **token 签名私钥**靠 JWKS 里的新旧重叠轮换，不重启：把新私钥写进 `APP_TOKEN_NEXT_SIGNING_KEY_FILE` 并 `up`（每个副本 30 s 内发布它的公钥）；至少一小时后把它挪到 `APP_TOKEN_SIGNING_KEY_FILE`、清空 next 键、再 `up`。iam 成员在自己的 schema 里记下签过名的每把钥的公钥，停止用它签名之后再继续发布访问令牌寿命加 60 s，所以切换前签的 token 仍能验过（contract-infra-iam `TOKENS.md`、[21-identity-provider.md](21-identity-provider.md)）。`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM` 退役。
- **OpenBao 来源**（以后再做）：AppRole 或 Kubernetes 认证、租约续期，放在同一份"用时才读"的契约后面。

**开发机**（已定）：提交一份用 SOPS 和 age 密钥加密的 `secrets.enc.yaml`；每个开发者用自己的密钥把它解密成 `.env`。密钥的值绝不打印、不记日志、不贴进对话。

## 备选方案

| 方案 | 是什么 | 许可证 | 对本项目 |
|---|---|---|---|
| 环境变量 + `.env`（已在用） | 最简单 | — | 除密钥的值以外，仍是配置面 |
| brickKit 挂载的密钥文件（`mount: file`，选它） | 值在文件里，路径在变量里；`up` 原地改写 | — | 所有密钥；两种目标上都能不重启轮换 |
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
- 在用的那一刻才从文件读的密钥，让轮换不必重启进程，也让值不出现在 `docker inspect`、Pod 的 env、进程转储和崩溃报告里，组件代码也不必知道密钥从哪来。
- `$endpoint:` 让知道版本和拓扑的 brickKit 去算每一个不是依赖的地址；手写的地址是 `brickkit.yaml` 的第二份拷贝，下一次发版就过时。

## 为什么不选其他

- **配置中心**：每个组件的运行期依赖，`config/` 之外的第二个事实源，"跑着的"不再等于"提交的"。
- **组件直接调 Vault**：每个组件都得学一个厂商 API，而且 Vault 的许可证变了；OpenBao 放在 SDK"用时才读"的契约后面能得到同样的效果，没有这些问题。
- **只有明文 `.env`**：密钥曾从它泄露进日志和对话；加密文件放进 Git，既能共享又不暴露。
- **密钥放环境变量**（brickKit 对 `secret: true` 的默认做法）：进程启动时就定了，轮换要重启（Kubernetes 上是一次 `brickkit.io/secret-digest` 滚动），能读进程环境的东西都看得到。
- **值里写运行期文件引用**（`@file:/run/secrets/<name>`，早先的设计）：需要一个 brickKit 生成文件之外的挂载；`mount: file` 给出同样可重读的文件，挂载也是生成的。

## 什么时候换

- 客户强制使用某个密钥平台：Kubernetes 上用 External Secrets Operator 加 `existingSecret`（什么都不改）；别的环境在 SDK"用时才读"的契约后面为该平台加一个适配器。
- Kubernetes 上由别的工具轮换密钥（cert-manager、External Secrets Operator）：用 `existingSecret` 指向它的 Secret；文件跟着轮换变，不需要 `up`。

## 怎么换

1. Kubernetes 加 External Secrets Operator：在 `config/<scope>-<name>.yaml` 里把该项写成 `{existingSecret: <name>, key: <key>}`。只有声明了 `secret: true` 的项接受这种写法。
2. 轮换：改 `config/` 里（或外部 Secret 里）的值，跑 `up`；什么都不重启。数据库口令：先 `ALTER ROLE … PASSWORD`，旧口令保持可用，直到过了 `PG_CONN_MAX_LIFETIME`。
3. 新来源（OpenBao 或别的平台）：在每个官方 SDK 里实现"用时才读"的契约，跑密钥一致性套件，再在配置里选用；组件代码不改。

## 一致性测试

套件 `tools/be-acceptance/conformance/secret/`（已定）：请求持续进行时，改写挂载的口令文件来轮换数据库口令，失败请求为零。组件套件检查（CP-CORE-14）：环境变量里没有任何密钥的值，每个 `secret: true` 键都是 `mount: file` 且以 `_FILE` 命名，换掉的密钥文件不重启就用上；门禁 `protocol-config-scan` 检查 `configSchema` 里生成的协议键段是最新的。

每个官方 SDK 里的测试，先写红：

- 有值但非法的整数让启动失败并点名键；
- 有两个成员配置错误的外壳一次报出两个错误，且不 panic；
- 密钥文件变了以后，30 s 内 SDK 返回新值，Go、Python、TypeScript 都一样；
- 变化之后读不了的密钥文件保留上一个有效值，记一条不含值的 ERROR，并计入 `be_secret_reload_failures_total`；
- 口令轮换后新连接成功，旧连接到最大寿命时退役。

## 相关决策

- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：共享连接键在 `config/vars.yaml` 里只写一次。
- [0107 族成员的地址是共享变量里的 `$endpoint:` 引用](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：族地址就是配置，由 brickKit 算出。
- [0109 规则写在语言中立的组件协议里，由黑盒套件检查](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md)：配置键和严格解析是组件协议的一部分。
- 计划新增：无。"没有配置服务器"是 brickKit 自己的设计原则，记在根目录 `AGENTS.md` 里。

## 已知限制

- 能查看容器的人都看得到非密钥的环境变量。能进入容器的人读得到密钥文件；Docker 宿主机上，能进到 `.brickkit/generated/secrets/` 的本机用户也读得到（顶层目录是 0700，下面的文件不是）。
- 以文件交付的密钥，brickKit 只在 Docker 和 Kubernetes 上测过。Podman，以及 SELinux 处于 enforcing 的宿主机（目录挂载可能需要重新打标签），都没测过；组件在那里读不到文件时，记下来反馈给 brickKit。
- 运行中的服务容器里有属主的口令文件，因为迁移容器拿到同样的挂载；brickKit 不做只给迁移的覆盖（FR06-013）。SDK 运行期从不读它。
- 轮换不是即时的：最多等 SDK 的 30 s 检查，Kubernetes 上再加 kubelet 的同步（通常一分钟内）。
- `file://` 在生成时读：改了源文件，在下一次 `up` 之前什么都不变；下一次 `up` 原地改写挂载的文件，不重启。
- `existingSecret` 只存在于 Kubernetes。
- 外壳里非文件的配置作为一个 JSON 值走密钥路径；密钥是文件，不在其中。
