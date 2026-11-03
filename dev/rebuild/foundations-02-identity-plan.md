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
| T2 | 设计两件事并写进线协议：令牌陈旧的依据；边缘的实现形态 | T1 | ⬜ |
| T3 | `infra/iam-casdoor` 补全：会话状态表、刷新与换取在会话锁内一次、改密码结束其他会话、失效推送、绑定的预期、开发换取的上线检查；换上 SDK alpha.53 | T2 | ⬜ |
| T4 | 边缘：按会话缓存令牌、接受失效推送、`TOKEN_STALE` 只重试一次、自定义请求头、`features` | T2、T3 | ⬜ |
| T5 | SDK 的准入：`TOKEN_STALE`、下游的 401 按可重试处理、带幂等键的重试 | T2 | ⬜ |
| T6 | 一致性套件：模拟身份提供方，登录剖面进黑盒套件 | T3、T4、T5 | ⬜ |
| T7 | 收尾与门槛核对 | 全部 | ⬜ |

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

### T3–T7

在 T2 定下之后各自写“要做到什么、验收、可能动到”。

## 全局约束

照第一项：
- 改动的循环；行为变了先改协议的条款与向量，再改 SDK；版本每次都升，按依赖顺序发布；
- 测试先断言前提成立；写在实现之后、第一次就绿的测试做一次改坏代码的反向检查（测试与验证的“一轮红绿与铁律”）；
- 进记录的运行当场存输出；热路径改了量一次；
- 这一阶段不新做业务组件；新建仓库先问。
