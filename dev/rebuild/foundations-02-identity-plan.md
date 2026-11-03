# 底层先行第 2 项：登录与身份

> 2026-11-03 起草并定稿，按 `f-plan`。阶段与推进方式见根 `AGENTS.md`“推进方式”一行；这一项做到下面的门槛后汇报，维护者确认后进第 3 项（权限）。

## 门槛与范围

| 门槛 | 这一项里指什么 |
| --- | --- |
| 安全 02 与协议 20 中登录相关的独立预期全过 | 安全 02 的 TI01–TI22 中与登录、令牌、身份链接、服务凭据相关的各条；协议 20 的 UI04–UI07、UI19–UI23、UI25、UI29 |

- **范围**（维护者 2026-11-03 定）：只做安全 02 与协议 20 中登录相关的预期，以及 `infra/iam-casdoor` 的补全与一致性套件的模拟身份提供方。
- **不在这一项**：安全 11 的身份成员切换（IM01–IM52）等真要接第二种身份产品时再做，要新建第二个身份适配组件的仓库，那时再问；成员切换的窗口时长随它。
- 安全 02 里属于事件、后台任务与外部来源的几条（TI15–TI19，例如伪造事件的 actor、重放工具、导出排队后停用、支付回调），分别归第 1 项已做的部分或第 3、4 项（权限、审计），定稿时逐条标出。

## 现状（2026-11-03 盘点）

- `infra/iam-casdoor` 3.0.15（`be-sdk-go` alpha.41），约 1 000 行 Go。
  - 已有：授权码加 PKCE 的浏览器登录，服务端会话（Cookie 只存摘要），按会话换取访问令牌，登出，JWKS，开发换取（只在 `IAM_DEV_EXCHANGE` 为真时注册）。
  - 测试：对真实 Casdoor 与 PostgreSQL 的端到端测试，覆盖登录、换取、空闲超时与登出。
- 组件设计（`docs/design.md`）写了、本版没做的：
  - 登出与停用向边缘推送失效；刷新在会话锁内只做一次、旧刷新令牌再用时撤销整串；
  - 作为授权的外部来源与水位来源：定期全量比较、补取、停用证据。
- 协议 20 的边缘一侧（按会话缓存令牌、推送失效、`TOKEN_STALE` 只重试一次、改变状态的请求要自定义请求头）：设计写明“由身份适配组件随附的边缘插件或旁挂进程实现”，还没有实现。
- `TOKEN_STALE`：入口组件在准入时按会话代次与账号的安全状态版本判断。组件从哪里得知这两个值（令牌声明、授权视图，还是身份来源的投影）要在定稿时对照安全 02、03 定。
- 一致性套件没有模拟身份提供方；SDK 的 `sectest` 有测试用的令牌签发与授权替身。

## 范围内的预期（读完安全 02 后逐条定）

| 预期 | 归属 | 这一项做什么 |
| --- | --- | --- |
| TI01–TI03、TI07、TI08、TI21 | SDK 的服务凭据与调用（mTLS、调用组件清单、请求级上下文、外壳） | T1 核对已有测试点名；缺的补测并改坏确认 |
| TI04 | SDK 的核验器（P8.1）与身份组件签发的几种凭据 | 访问令牌、Casdoor 的 ID 令牌、会话换取的凭据、服务凭据互相替换都被拒 |
| TI05、TI06 | SDK 的守卫与调用 | 公开入口填的受信字段无效；服务在用户路径上漏了用户凭据时不降级 |
| TI10 | 身份组件（令牌不带角色与部门） | 令牌声明的核对；属性的新鲜度归第 3 项 |
| TI11 | 身份组件的账号绑定 | 相同邮箱、登录名或同 subject 不同 issuer 都不自动接管 |
| TI20 | SDK（P8.2 的公钥刷新、证书到期） | 核对与补测；长连接的撤销归第 3 项（安全 03） |
| UI04–UI07、UI19–UI23、UI28、UI29、UI31 | 身份组件、边缘、SDK 的准入 | 本项主体 |
| UI25 | 装配工具与边缘 | `features` 由装配工具生成，只给已登录的会话 |
| 不在本项 | TI09、TI12–TI14（任职、初始管理员、本人自审、属性）→ 第 3 项；TI15–TI19（事件与回调）→ NATS 的权限清单记入基础资源的待办，其余随第 3、4 项；TI22 → 成员切换 | — |

## 任务

| # | 任务 | 依赖 | 状态 |
| --- | --- | --- | --- |
| T1 | 覆盖地图：上表每条落到哪个测试；已有的点名、缺的列出 | — | ✅ 2026-11-03 |
| T2 | 设计两件事并写进线协议：令牌陈旧的依据；边缘的实现形态 | T1 | ✅ 2026-11-03（`be-protocol` alpha.53） |
| T3 | `infra/iam-casdoor` 补全：会话状态表、刷新与换取在会话锁内一次、改密码结束其他会话、安全状态版本与账号状态事件、`SessionService`（换取、已结束的会话）、按 issuer 与 subject 绑定、开发换取的上线检查；换上 T5 发布的 SDK | T2、T5 | ✅ 2026-11-03（3.0.16） |
| T4 | 边缘（`be-edge`）：按会话缓存令牌、拉取已结束的会话、`TOKEN_STALE` 只重试一次、自定义请求头、`features` | T2、T3 | ✅ 2026-11-03（`be-edge` v3.0.0-alpha.1、`be-ops` v3.0.0-alpha.1；对真实 iam-casdoor 的联调随 T6） |
| T5 | SDK：`be_sv` 的核验、准入的 `TOKEN_STALE`、下游的 401、`SessionService` 的生成代码与已结束会话的读取、补测（T1 的缺口） | T2 | ✅ 2026-11-03（`be-sdk-go` alpha.54；Python 随第 6 项） |
| T6 | 一致性套件：模拟身份提供方，登录剖面进黑盒套件 | T3、T4、T5 | ✅ 2026-11-03（`be-acceptance` 1.0.38；浏览器路径 `experiment-data/16-05-*`） |
| T7 | 收尾与门槛核对 | 全部 | ✅ 2026-11-03（门槛表、复盘 [retro-foundations-02.md](retro-foundations-02.md)；等维护者确认） |

### T1 覆盖地图

- **要做到什么**：范围内每条预期，写明由哪个测试（SDK、组件、套件）验证，已有的照点名核对，缺的列成后面任务的输入。
- **验收**：地图写进本计划；已有的测试按点名跑过；改坏确认放在补测时做。
- **结果**（2026-11-03，`be-sdk-go` alpha.53、`infra/iam-casdoor` 3.0.15）：下表点名的 SDK 测试（`identity`、`grpcx`、`httpx`、`calls`）与 iam-casdoor 的单元测试都跑过、全绿；`guard` 包自己没有测试，准入由 `launcher.TestOthersSeeNothingAndFieldsFollowTheSegments` 经真实的启动器覆盖。

| 预期 | 已有的测试 | 缺口 → 归哪个任务 |
| --- | --- | --- |
| TI01 伪造 `be-caller`、无证书 | `grpcx.TestConnectionsWithoutAValidIdentityAreRefused`（无 TLS、别的部署的证书）；正例 `TestOnlyPermittedComponentsMayCall` | 系统面根本不读 `be-caller`（调用者只取自证书），没有测试写明这一点 → T5 补一例：带获准组件名的 `be-caller`、证书是未获准的组件，拒绝 |
| TI02 同根别的组件、别的部署的证书 | `TestOnlyPermittedComponentsMayCall`、`TestAnyComponentAdmitsEveryComponentOfTheDeploymentOnly`、`TestConnectionsWithoutAValidIdentityAreRefused` | 无 |
| TI03 客户端连到错误的目标 | `TestConnectionsWithoutAValidIdentityAreRefused`（客户端期望 finance、服务端是 inventory）、`TestClientsSendTheTargetsDerivedNameAsSNI` | “失败时不发送用户凭据”没有断言 → T5 |
| TI04 几种凭据互相替换 | 向量 `jwt-verify` 的 26 例（`typ`、`alg`、`iss`、`aud`、时效、`sub` 各自的负例）经 `identity.TestJWTVerifyVectors` | Casdoor 的 ID 令牌没有作为一例出现（它的 `typ`、`iss`、`aud` 都不同，被现有的负例分别覆盖）→ T3 在端到端测试里把真实的 ID 令牌交给 SDK 的核验器，拒绝；没有刷新令牌与服务令牌（服务身份是 mTLS），写明 |
| TI05 公开入口填受信字段 | 向量 `roles-claim-ignored` | 用户面的请求头（`be-caller`、自称的 actor）不进上下文、公开路由不带用户上下文，没有测试 → T5 |
| TI06 漏了用户凭据不降级 | `calls` 的 `ForwardUser` 没有凭据时报错（代码 `calls/http.go`），没有测试；被调用方只有 `user` 模式，必须自带用户凭据 | → T5 补测；`service_proxy` 模式是单独的能力 `call-mode-service-proxy`（`not_implemented`），不在本项 |
| TI07 服务凭据与 `be-caller` 不同 | 同 TI01：`be-caller` 不读 | 同 TI01 的补测 |
| TI08 复用连接交替两个用户、派生并发任务 | 没有 | → T5：同一连接交替两个用户的请求，下游各自收到自己的凭据；派生的任务缺上下文时 `ForwardUser` 报错而不是系统主体 |
| TI10 令牌不带角色与部门 | `iam.TestTokensPassTheSDKsVerification`（签发的声明）；向量 `roles-claim-ignored` | 签发的令牌只有 `iss aud sub iat nbf exp jti`，已满足；新鲜度归第 3 项 |
| TI11 不自动接管 | 没有 | **缺陷**：`iam_account` 的唯一键是 `(provider, provider_subject)`，`provider` 固定写 `casdoor`，不含 issuer：换一个 Casdoor 实例、同一 subject 会落到同一个平台主体。邮箱与登录名不参与绑定（只更新 `username`），这一半已满足 → T3 改成按 `(issuer, subject)` 绑定并补测 |
| TI20 到期、续期失败、未知密钥、时钟 | 向量的 `expired*`、`not-yet-valid`、`kid-unknown`；`TestStaleKeysAreNotUsed`（1 小时）、`TestUnknownKIDRefreshIsRateLimited`、`TestConcurrentRequestsWaitForTheRefreshInFlight`；`TestTheServerEndsEachConnectionAfterItsAgeAndNoCallFails` | 过期的服务证书、证书文件轮换后重读没有测试 → T5 |
| TI21 外壳成员共进程 | `shell.TestAMemberWithoutTheSecurityKeysSharesTheShell`、`TestEachMemberServesItsSystemSurfaceOnItsOwnPort` | 同一外壳里成员甲调成员乙，乙看到的调用者是甲（不是外壳），没有测试 → T5 |
| UI04 脚本拿不到令牌 | Cookie 是 HttpOnly（e2e 断言） | **缺口**：换取接口 `POST /api/iam/session/token` 是公开路由，同源的脚本带上 Cookie 就能在回答里读到访问令牌。换取只能由边缘调用 → T2 定边缘与身份组件之间的接口时一起定（例如改为系统方法、只许边缘调用），T3、T4 实现 |
| UI05 两个标签页同时刷新 | 没有（现在每次换取都签一枚新令牌，没有刷新令牌） | → T3（会话锁内一次）、T4（边缘按会话缓存） |
| UI06 缺自定义请求头 | 没有 | → T4 |
| UI07 登出后的旧 Cookie | `iam.TestEndToEndAgainstCasdoor`（登出后换取答 401） | 边缘一侧（缓存的令牌随登出失效）→ T4 |
| UI19、UI20、UI29 身份组件重启、失效推送丢失 | 没有 | → T4（边缘的缓存与回答）、T6（套件里停身份组件） |
| UI21 邮件链接 | `httpx.TestCookiesAndRedirects`（登录的跳转） | Lax Cookie 跨站顶层导航照常带上；改变状态仍要自定义请求头 → T4 |
| UI22、UI23 `TOKEN_STALE` | 没有（SDK 没有这个原因，令牌没有安全状态版本） | → T2 定依据，T3 签发，T4 重试一次，T5 准入 |
| UI25 `features` | 没有 | → T4；`features` 由谁生成（BrickKit 还是 `be-ops`）在 T4 开头查清 |
| UI28、UI31 下游 401、带幂等键的重试 | 幂等键：`idem` 的测试（CK-IDEM-01..04） | 下游 401 按可重试的“暂时无法确认”处理没有 → T5 |
| 套件 | `be-acceptance` 的剖面里没有任何 CK-ID 检查（CK-ID-01..04 只由 SDK 自己的测试点名；CK-ID-02 只查了日志，没查追踪；CK-ID-03 没有测试点名） | → T6 的登录剖面：模拟身份提供方的 JWKS 轮换（01）、日志与追踪（02）、用户凭据调系统方法（03）、证书（04） |

### T2 两件设计

- **令牌陈旧的依据**：令牌带签发时账号的安全状态版本。改密码、重置或移除 MFA、强制登出时版本加一，其他会话结束，当前会话换发新令牌。入口组件拿令牌的版本与当前版本比。当前版本的来源有三种候选：授权视图携带（授权组件本来就以身份成员为来源）、身份成员的投影、每次准入向身份成员查询。要对照安全 03 的视图与水位、D57（授权组件不进同步路径）选定。
- **边缘的形态**：`f-research` 比较几种候选：
  - Traefik 的中间件插件（Yaegi 解释执行，能包住下一个处理器、缓存请求体后重放）；
  - 挡在 Traefik 后面的反向代理旁挂进程（Go，身份组件仓库里多一个二进制）；
  - 转发认证加缓存。转发认证重放不了请求，推理上就不满足“只重试一次”，写下理由。
  - 先适配、再性能、再新；量一次每个请求多付的代价。
- **验收**：两条写进 AI 决定的台账（A 编号）与线协议第 08 章（令牌声明、准入规则、边缘与身份组件之间的推送与换取接口），带检查编号与向量；COMPAT 记一行。牵到授权视图的部分与第 3 项衔接的方式写明。

#### 令牌陈旧的依据（定稿，2026-11-03；条款 P8.25–P8.27）

- **一个整数，走已有的路**：身份成员为每个账号保存安全状态版本 `security_version`（从 1 起，只增）。改密码与重置密码、重置或移除 MFA 因素、强制登出（一个或全部会话）、停用与冻结时加一。签发的访问令牌带声明 `be_sv` = 签发时的版本。版本随账号状态记录 `be.security.account_status`（安全 09a，本来就经身份成员的发件表进授权组件）多一个必填字段 `security_version`；授权组件把它放进视图的 `SubjectEntry`（多一个字段 `security_version`）。
- **准入**：入口组件核验令牌、取到视图之后，`SubjectEntry.security_version > be_sv` 时答 `401 TOKEN_STALE`，在任何副作用之前。视图里没有这个主体，或视图还没有这个字段（第 3 项之前的授权成员），按 0 处理，不判陈旧。缺 `be_sv` 的令牌答 `TOKEN_INVALID`（P8.1 多一条）。
- **会话代次只留在身份成员里**：协议 20 写的“会话代次推进，或账号的安全状态版本已变”，合成一个账号版本。改密码时其他会话在身份成员里结束（换取会失败，边缘返回“需要重新登录”），当前会话的下一次换取拿到新版本的令牌；强制登出一个会话也加版本，账号的其他活着的会话因此在下一个请求换取一次，用户无感（强制登出少见，代价可以接受）。组件不需要每个会话的状态。
- **上界**：正常时是“事件到授权组件、视图续期”的几秒；最坏是来源水位的 `D_src`（高风险 60 秒、普通读取 10 分钟）加视图有效期。普通读取的最坏上界长于令牌有效期（5 分钟），那时由令牌到期界定。产品说明照这两个数写。
- **不采用**：
  - 每个入口组件各建一份身份的投影：每个组件多一份来源、水位与对齐，事实却与授权视图里已有的账号状态同源；
  - 每次准入向身份成员查询：把身份成员放回每个请求的同步路径，与 D61 的理由相反；
  - 令牌里带会话代次、视图里带每个会话的状态：视图按主体组织，按会话放进去，视图随在线会话数变大，换来的只是强制登出一个会话时别的会话少换取一次。
- **给第 3 项的硬依赖**（T6 发现）：Python 组件收视图时按它那份协议副本（alpha.45）的 schema 校验，`SubjectEntry` 不许多出 `security_version`，会拒收整份视图。所以授权成员往视图里写版本之前，`be-sdk-python` 的协议副本先到 alpha.53 以上（第 6 项的这一部分排在第 3 项写版本之前）。
- **与第 3 项的衔接**：本项定线上的字段（令牌的 `be_sv`、账号状态记录与视图的 `security_version`）与 SDK 的准入，用 `sectest` 的视图替身验证；授权成员把版本写进视图、来源水位覆盖它，在第 3 项做，那之前真实部署里 `TOKEN_STALE` 不会出现（按 0 处理），写进 COMPAT。
- **kb**：认证篇“对外的自包含令牌……每个请求查一次撤销的时间点”（`zh/04-identity-and-access/02-authentication/00-decisions.md` D2 的建议）：这里的“查”是查本地的授权视图，不是一次网络调用。

#### 边缘与身份成员之间的接口（定稿，2026-11-03；条款 P8.28、第 11 章）

- **换取改为系统方法**：`POST /api/iam/session/token` 是公开路由，同源的脚本带上 Cookie 就能在回答里读到访问令牌（T1 的 UI04 缺口）。改为标准系统方法 `be.session.v1.SessionService/Exchange`（消息定义在 `be-protocol` 的 `proto/`，与 A115 的补取同一种做法：任何身份成员都实现同一个方法，边缘不随身份产品变）：请求带会话 Cookie 的摘要（SHA-256，身份成员本来只存摘要），回答令牌、到期时刻、主体与会话的最晚结束时刻，或 `SESSION_ENDED`；调用组件只有边缘。经 mTLS，浏览器到不了系统面。用户面的公开换取路由删掉（开发换取 A101 不变）。
- **失效改为边缘按游标拉取**：设计写的是身份成员向边缘“推送”。推送要知道每个边缘实例在哪里（BrickKit 没有注册中心，边缘可以有几个副本），推送丢失还要另有兜底。改为 `SessionService/Ended`：每个边缘实例按自己的游标每 `P_inv`（起始 1 秒）拉取一次“游标之后结束的会话摘要”；身份成员把会话的结束按提交后的序号记下，保留不短于令牌的最长有效期加余量（之后再拉也没有意义：缓存的令牌已到期）。游标落在保留期之前时，回答“游标过期”，边缘清空全部缓存（每个会话下一次请求换取一次）。上界：身份成员可用时 `P_inv`；不可用时不会有新的结束（结束都在身份成员里办理），已有的缓存照用到令牌到期，与 D61 一致。
- **登出**：经边缘的登出请求，边缘在转发给身份成员之后立即丢弃这个会话的缓存，不等下一次拉取。

#### 边缘的形态（调研与实测，2026-11-03）

- **排除**：Traefik 的 WASM 插件（http-wasm 的 ABI 的 19 个宿主函数里没有出站网络，换不了令牌；只交给下一个处理器一次，重放不了；http-wasm.io/http-handler-abi，读于 2026-11-03）；转发认证（重放不了请求）。
- **每个请求多付的代价**（`experiment-data/16-01-edge-session-cost/`，Traefik v3.0.4，每秒 2 000 次，性能电源模式，6 轮成对交替，命中缓存时的最低开销）：Yaegi 中间件多 22–35 µs 的边缘 CPU、延迟看不出差别；编译的旁挂代理放在 Traefik 前面多 166 µs、p50 多 0.14 ms，放在后面绕回 Traefik 多 356 µs、p99 多 0.4 ms。作为参照，空的后端每个请求 59–78 µs。
- **定了**（维护者 2026-11-03）：Yaegi 插件为主。核心写成只用标准库的 Go 包，换别的边缘产品时套一层旁挂外壳，两种实现跑同一套检查。先做两个小实验，任何一个不成立就改用旁挂：从 Yaegi 经 mTLS 调 gRPC 的系统方法（手写 HTTP/2 上的 gRPC 分帧，grpc-go 用了 `unsafe`）；动态配置重载（Docker 的服务增减都会触发）之后插件的状态还在。

### T3–T7

> 2026-11-03 T2 定下之后写。顺序变了：T5 排到 T3 之前，因为 iam-casdoor 要用 SDK 提供的 `SessionService` 生成代码与“按位置读已结束会话”的读取器；T3、T4 的“失效推送”按 A118 改为“已结束会话的拉取”。

#### T5 SDK（`be-sdk-go`，随后 `be-sdk-python`）

- **要做到什么**：组件换上新版 SDK 就满足 P8.1 的 `be_sv`、P8.25、P8.26；身份成员能用 SDK 实现 `SessionService`。
- **内容**：核验器要求 `be_sv`（向量 `jwt-verify` 新的 5 例）；视图的 `SubjectEntry.security_version` 解析与准入比较（向量 `token-stale`），`TOKEN_STALE` 在任何副作用之前；`calls` 的用户面与系统面调用把下游的 401 换成 `AUTHORIZATION_UNPROVABLE`；导出 `be.session.v1` 的生成代码；发件表上按位置分页读一条流的读取器（水位来源的 `page` 已有同类实现，抽成共用的）；`sectest` 的令牌带 `be_sv`、视图替身能设版本。T1 列的补测：`be-caller` 不参与判断（TI01、TI07）、目标不符时不发送用户凭据（TI03）、用户面的自称字段不进上下文（TI05）、`ForwardUser` 缺凭据报错（TI06）、同一连接交替两个用户（TI08）、过期的服务证书与证书文件轮换（TI20）、外壳里成员之间的调用者（TI21）。
- **验收**：向量全过；新测试先红后绿，写在实现之后的做改坏的反向检查并存记录；`features.json` 的 `token-staleness` 为 verified；`make vet`、`make test`、`make test-integration` 全过。
- **回退**：没有数据迁移；组件不升级就照旧（但实现新协议的组件拒绝不带 `be_sv` 的令牌，所以身份成员要先签发它：T3 之前不让其他组件升级到这一版）。
- **可能动到**：`identity/`、`guard/`、`authz/view.go`、`calls/`、`events/`（读取器）、`sessionpb/`（新）、`sectest/`、`features.json`。

- **结果**（2026-11-03）：`be-sdk-go` alpha.54（`be-protocol` alpha.53；COMPAT 记在 alpha.54）。`make vet`、`make test`、`make test-integration`（33 个包）全过，输出在 `foundations-02-data/t5/test-integration.txt`。新规则各改坏一处都变红（`foundations-02-data/t5/mutations.txt`）；反向检查查出两处：`ReadAfter` 的“超过末尾”判断是多余的（删掉），“别的纪元”缺新纪元里已有行的一例（补上）。T1 的 SDK 缺口都补了测试：TI01、TI03、TI05–TI08、TI20、TI21。
- **Python 移到第 6 项**：`be-sdk-python` 的协议副本还在 alpha.45，换到 alpha.53 会一起带进 alpha.46 以来的 P7.23、迁移 0011 与 0012、第 9 章的水位，这些本来就排在第 6 项（Python 剖面）。它的核验器忽略不认识的声明，带 `be_sv` 的新令牌照样接受，所以 T3 之后 Python 组件照常；在那之前它不判 `TOKEN_STALE`、不改写下游的 401，它的 `features.json` 里还没有 `token-staleness` 这项能力，T6 的登录剖面只对声明了它的 SDK 跑这几项（与第一项的水位来源同样处理）。

#### T3 `infra/iam-casdoor`

> 范围（2026-11-03，AI 定，待复核）：改密码由身份适配组件办理（`POST /api/iam/password`：会话 Cookie 加旧密码，用登录应用的凭据调 Casdoor 的 `set-password`，Casdoor 仍核对旧密码，小实验 `experiment-data/16-03-*`），所以它知道哪个是当前会话：加版本、结束其他会话、当前会话的下一次换取拿到新版本。用户在 Casdoor 自己的页面改的、在 Casdoor 控制台停用的，要靠定期全量比较才发现（Casdoor 没有可靠的变更序号，见组件设计），与停用的拉取、证据、作为授权内部来源的水位一起做，归第 3 项；那时按 `LastChangePasswordTime` 发现改密码，结束全部会话。强制登出与 MFA 的重置要授权的管理操作，也归第 3 项；本项把它们共用的“加版本、结束会话、发出账号状态”做成一个入口。

- **要做到什么**：身份成员满足 P8.27、P8.28 与 T1 的 TI11，浏览器拿不到令牌（UI04）。
- **内容**：账号表加安全状态版本与签发者；按 `(issuer, subject)` 绑定，同邮箱、同登录名不接管；会话表加结束原因与会话代次，换取在会话行锁内；`SessionService` 两个方法（调用组件 `infra/edge`），会话结束写进流 `be.session.ended`；改密码（经 Casdoor 的回调或拉取得知）结束其他会话并加版本；账号状态事件 `infra.iam.account_status_changed.v1` 带版本；删掉公开的换取路由；开发换取的上线检查（A101）。
- **验收**：对真实 Casdoor 与 PostgreSQL 的端到端测试覆盖 UI05、UI07、UI22 的身份一侧与 TI04（真实的 ID 令牌交给 SDK 核验器被拒）、TI11；数据迁移先在副本上跑。
- **回退**：迁移可逆（加列与新表）；回退版本前先停边缘。
- **可能动到**：`iam/` 全部、`migrations/`、`docs/design.md`、组件定义与注册表（`infra/edge` 身份）。

- **结果**（2026-11-03）：`infra/iam-casdoor` 3.0.16（`be-sdk-go` alpha.56）。SDK 顺带加了两样：`calls.Request.Form`（alpha.55：Casdoor 的 `set-password` 只读表单，密码与客户端密钥不能放进 URL）、`events.ParseEpoch`（alpha.56：边缘带回的游标）。端到端测试（真实的 Casdoor 4.1.0、PostgreSQL、NATS）覆盖：`be_sv`；TI04（Casdoor 的 ID 令牌在 `typ` 被拒）；TI11（别的签发者的同一 subject 不接管，旧行归配置的签发者）；UI04（公开换取路由没了）；边缘经 mTLS 的 `Exchange`（别的组件答 `PERMISSION_DENIED`，伪造的摘要答 `SESSION_ENDED`，`renew_idle` 为假不续期）；改密码（旧密码错时什么都不变；其他会话结束、当前会话拿到版本 2、账号状态进发件表、Casdoor 有了新密码）；空闲超时与登出出现在 `Ended` 里。十处改坏都变红（`foundations-02-data/t3/mutations.txt`）。第一次跑时 `Ended` 在提交后立即读不到改密码结束的会话：行提交之后才编号，读的一方要反复拉（测试改为像边缘一样拉，期望不变）。
- **开发换取的上线检查**（A101）：没有新加机制，仍按 `BRICKKIT.md` 的“上线检查”与手册；归 T7 核对是否要做成检查。

#### T4 `be-edge`

- **要做到什么**：P11.1–P11.10 在 Traefik v3.0.4 上成立。
- **内容**：只用标准库的核心包（缓存、换取的单飞、重放、请求头、`features`、`Ended` 的拉取循环、手写的 gRPC 分帧）；Traefik 插件外壳；旁挂外壳只留形状；测试同时用 Go 编译器与 `yaegi test` 跑；向量 `edge-flow`。
- **验收**：核心对向量全过；在 Traefik 容器里对真实的 iam-casdoor 跑通 CK-EDGE-01..07；每个请求的代价复测一次（命中缓存时不超过 16-01 的插件读数加波动）。
- **仓库**：`brickKit/be-edge`（维护者 2026-11-03 放行，已建，子模块 `tools/be-edge`，只有 README 与许可证）。
- **可能动到**：新仓库；`infra/traefik/` 的静态配置（本地插件、证书）；装配工具生成的路由标签（中间件）。

- **结果**（2026-11-03）：`be-edge` v3.0.0-alpha.1：只用标准库的核心与 Traefik 的 Yaegi 插件（`.traefik.yml` 要写 `basePkg: edge`，否则 Traefik 按导入路径的最后一段 `v3` 找包）。测试四套：Go 编译器与 `yaegi test`（v0.16.1）下的单元测试；`tests/` 子模块经插件的公开入口对 grpc-go 的 `SessionService`（mTLS）跑协议向量 `edge-flow`、身份不符的服务端、轮询、证书轮换；真实 Traefik v3.0.4 容器里的插件（注入、`BE-Request`、重放一次、已结束会话、配置重载后缓存还在、日志里没有 Cookie 与令牌）。改坏 17 处都变红（`foundations-02-data/t4/mutations.txt`）；反向检查查出重放的测试只比了两枚令牌不同（收紧为必须是第二次换取的那一枚）。
- **查到的坑**：
  - Yaegi 里标准库回调解释执行的代码（`tls.Config` 的 `GetClientCertificate`、`VerifyConnection`）在握手中 panic（`reflect.Set: value of type *tls.CertificateRequestInfo is not assignable ...`），整个 Traefik 进程退出；单元测试与不连身份成员的手工复现都看不出，只有对真实服务器握手时才出。改为静态的 `tls.Config`、证书文件变了就换传输；轮询的 goroutine 加了 `recover`（Traefik 的恢复中间件管不到它）。写进 `be-edge` 的 `AGENTS.md`。
  - Traefik 把插件写到标准错误的每一行都记成 ERR：普通提示改写到标准输出。
- **代价**（`experiment-data/16-04-edge-plugin-cost/`，性能电源模式，成对交替）：命中缓存时每个请求多 90 µs 的边缘 CPU，p50、p99 各多 0.1 ms 左右；其中约 36 µs 是拦截器（原生的反向代理调解释执行的写入方法），`r.Clone` 量不出差别（去掉它的变体没有保留）。**没达到本任务自定的验收**（不超过 16-01 的插件读数加波动，那次只量了最简单的一步）；仍低于 16-01 里编译的旁挂代理的最低读数（放在前面多 166 µs，而那只是一个什么都不做的代理）。如实记下，汇报时说明。
- **`features`**：`be-ops` 原来只有一行旧设计（写进身份适配层的 `enabledComponents`），与协议 20 相反；新加 `be-ops features --root <项目> --out <文件>`，从 `brickkit.yaml` 列出选中的组件与精确版本（协议 20 写的“能力”组件清单里还没有地方声明，前端用到时再定）。
- **接进部署**（`infra/traefik` 的插件与证书、`infra/edge` 的服务证书、路由生成器挂中间件）：代表部署的单元格还没有边缘（实验第 5 步起外部请求经测试用的入口），随 T6 在单元格里接上，与真实的 iam-casdoor 一起跑。

#### T6 一致性套件

- **要做到什么**：登录剖面进黑盒套件；浏览器路径前后打通一次。
- **拆法**（2026-11-03，AI 定）：
  1. `be-sdk-python` 的测试部署 `besdk.testing`（只动测试辅助，不换协议副本）：令牌带账号的 `be_sv`；`security_change`；公钥集能轮换、记下被取的次数。
  2. 探针：Go 探针换到 `be-sdk-go` alpha.56，加一条代表用户调下游的路由（CK-ID-06）。
  3. 登录剖面（`be-acceptance` 的 `profile/identity.py`）：CK-ID-01（轮换）、02（日志里没有凭据）、03（用户凭据到不了系统面）、04（证书与调用组件）、05（令牌陈旧，写请求没有副作用）、06（下游的 401）；05、06 只对 Go，Python 判“不适用”（它的协议副本还没有 P8.25、P8.26，随第 6 项）。
  4. 浏览器路径的端到端：真实的 Casdoor、`infra/iam-casdoor`、Traefik 加 `be-edge`、Go 探针，测试部署出证书与授权视图（视图里版本的更新由测试部署代做，授权成员消费账号状态是第 3 项）：CK-ID-07、CK-EDGE-01..07 与 UI04–UI07、UI19–UI23、UI25、UI29。
- **验收**：Go 与 Python 的探针按各自的能力通过；改坏 SDK 的对应规则时剖面变红；端到端跑通并存输出。
- **第 1–3 步的结果**（2026-11-03）：`be-sdk-python` a45（只动 `besdk.testing`）；套件原来钉在 a20，一并换到 a45，第一项的四个剖面照常符合（`foundations-02-data/t6/item1-profiles-a45.txt`）；`test/probe-go` 及变体 3.2.33（SDK alpha.56）；`be-acceptance` 1.0.38 的身份剖面：Go 探针 CK-ID-01..06 全部通过，Python 探针 01..04 通过、05 与 06 不适用（`identity-profile.txt`）。反向检查（`profile-mutations.txt`）：在本地 SDK 源码里逐条改坏 P8.25、P8.26、P8.2、P8.6、P8.3，各自对应的检查失败；Python 的 P8.2 改坏一处同样。反向检查本身查出三处“红而没打中”：等不到 401 时 CK-ID-05 判成“未运行”而不是“失败”（观察改为记下最后一次的回答）；两处改坏让 SDK 编译不过（改在比较本身，并先确认能编译）；`-k py` 同时匹配了模块名、把 Go 那一例也跑了。

- **第 4 步的结果**（2026-11-03，`experiment-data/16-05-login-flow/`）：浏览器路径全部真实部件，20 步都成立：UI04、UI05、UI06、UI07、UI19、UI21、UI22、UI23、UI25、UI29 与 CK-EDGE-01..07。改密码后“当前会话透明续上”先加了前提断言（探针恰好拒过一次旧令牌、边缘恰好换取一次），防止“绿而没测到”。视图里版本的上调由测试部署代做（第 3 项接上）。没在这里覆盖的：UI20（按构造：缓存条目在令牌到期前 30 秒作废）、UI28 与 UI31（下游的 401 是 CK-ID-06；带幂等键的前端重试要等前端）、CK-ID-07 的调用者检查（iam-casdoor 的端到端测试）。

#### T7 收尾

- **门槛核对**：上面“范围内的预期”每一条有通过的测试；COMPAT、`features.json`、组件索引、交接更新；复盘；实测记录（16-01、16-02）交 kb。
- **核对结果**（2026-11-03）。“SDK”指 `be-sdk-go` alpha.56 的测试，“剖面”指 `be-acceptance` 1.0.38 的身份剖面（Go 与 Python 两种探针），“浏览器路径”指 `experiment-data/16-05-login-flow`；新写的测试都做过改坏的反向检查（`foundations-02-data/t3`–`t6` 的 mutations）：

| 预期 | 由什么验证 | 结论 |
| --- | --- | --- |
| TI01、TI07 伪造 `be-caller`、身份与标签不符 | SDK `grpcx.TestTheCallerIsTheCertificateNotALabel`、`TestConnectionsWithoutAValidIdentityAreRefused`；剖面 CK-ID-04（未获准的组件） | 过 |
| TI02 别的组件、别的部署的证书 | SDK `grpcx` 的三个证书测试；剖面 CK-ID-04（别的根、别的部署） | 过 |
| TI03 连到错误的目标 | SDK `grpcx.TestAWrongTargetGetsNothing`；`be-edge` `TestAServerWithAnotherIdentityIsRefused` | 过 |
| TI04 凭据互相替换 | 向量 `jwt-verify`（31 例，含 `be_sv` 的 5 例）；iam-casdoor 端到端：Casdoor 的 ID 令牌在 `typ` 被拒 | 过 |
| TI05 公开入口填受信字段 | SDK `launcher.TestOthersSeeNothingAndFieldsFollowTheSegments`（自称的头不进上下文、公开路由没有用户） | 过 |
| TI06 漏了用户凭据、下游的拒绝 | SDK `calls.TestForwardingWithoutAUserCredentialIsNotSent`、`TestADownstream401ForTheUserIsUnprovable`；剖面 CK-ID-06（Go） | 过（Python 随第 6 项） |
| TI08 复用连接交替两个用户 | SDK `launcher` 同一测试（同一条连接、四次交替） | 过 |
| TI10 令牌不带角色与部门 | iam-casdoor `TestTokensPassTheSDKsVerification`；向量 `roles-claim-ignored` | 过（属性的新鲜度归第 3 项） |
| TI11 不自动接管 | iam-casdoor 端到端：别的签发者的同一 subject 不接管、旧行归配置的签发者 | 过 |
| TI20 到期、续期、未知密钥 | SDK `identity` 的公钥测试、`grpcx` 的过期证书与轮换；剖面 CK-ID-01（两种探针）；`be-edge` 证书轮换 | 过（长连接的撤销归第 3 项） |
| TI21 外壳成员共进程 | SDK `shell.TestMembersOfOneShellCallEachOtherAsThemselves` | 过 |
| UI04 脚本拿不到令牌 | iam-casdoor 端到端与浏览器路径：公开换取路由不存在（501） | 过 |
| UI05 两个标签页同时 | 浏览器路径：六个同时，一次换取；`be-edge` `TestConcurrentMissesExchangeOnce` | 过 |
| UI06 缺自定义请求头 | 浏览器路径；`be-edge` 单元与向量 | 过 |
| UI07 登出后的旧 Cookie | 浏览器路径；iam-casdoor 端到端 | 过 |
| UI19 身份适配组件重启 | 浏览器路径：停掉时有缓存的会话照常 | 过（`D_src_high` 的部分归第 3 项） |
| UI20 失效没能传到边缘 | 按构造：缓存条目在令牌到期前 30 秒作废（`be-edge` `TestATokenIsNotUsedInItsLastSeconds`）；拉取失败时照用缓存的路径（`TestEndedSessionsAndLogoutDropTheirTokens`） | 过（没有黑盒地等一个令牌有效期） |
| UI21 邮件里的链接 | 浏览器路径：不带请求头的 GET 照常 | 过 |
| UI22 改密码 | 浏览器路径（当前会话透明续上，前提断言：恰好一次 401、一次换取）；iam-casdoor 端到端；剖面 CK-ID-05（Go） | 过（视图里的版本由测试部署代做，第 3 项接上） |
| UI23 重试仍陈旧、会话已结束 | 浏览器路径（另外两个会话）；向量 `edge-flow` 的 `stale-twice` | 过 |
| UI25 `features` | 浏览器路径（`be-ops features` 生成，边缘只给活着的会话） | 过 |
| UI28 下游的 401 | 剖面 CK-ID-06；边缘只为 `TOKEN_STALE` 重放（向量 `edge-flow`） | 过（Go；Python 随第 6 项） |
| UI29 换取时身份适配组件在重启 | 浏览器路径：503，会话保留，回来后照常 | 过 |
| UI31 带幂等键的自动重试 | 后端一半：下游 401 答可重试的 503（CK-ID-06）、命令幂等（第一项的 CK-IDEM）；前端一半随前端 | 后端过，前端未做 |

- **还有的尾巴**（不挡门槛，各有去处）：Python SDK 的 P8.25–P8.28 随第 6 项，且要排在第 3 项往视图里写版本之前；授权成员消费账号状态、来源水位覆盖身份、Casdoor 侧变更的全量比较、强制登出与重置第二因素归第 3 项；单元格接上边缘（`infra/traefik`、`infra/edge` 证书）在代表部署下次接入边缘时做；开发换取的上线检查（A101）仍按手册的清单，没有做成自动检查；插件的代价没达到 T4 自定的验收（见 T4）。

## 全局约束

照第一项：
- 改动的循环；行为变了先改协议的条款与向量，再改 SDK；版本每次都升，按依赖顺序发布；
- 测试先断言前提成立；写在实现之后、第一次就绿的测试做一次改坏代码的反向检查（测试与验证的“一轮红绿与铁律”）；
- 进记录的运行当场存输出；热路径改了量一次；
- 这一阶段不新做业务组件；新建仓库先问。
