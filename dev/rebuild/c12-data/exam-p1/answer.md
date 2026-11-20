# C12 P1 设计考试的答卷（摘录）

考生：一个没参与写作的子代理（2026-11-20，只读文件），考 `components/frontend/pc/docs/design.md`（FP01–FP16，提交 `ad3626d`），对照协议 20、前端技术栈、边缘、边界卡、测试规范、线协议第 03、08、11、17 章、be-edge、身份成员的登录、授权组件的视图、be-ops 的 features、D17、D24、D34、D61、D68。处理待写 `result.md`。

## 必须改

- **M1** 会话结束后浏览器留着 `be_session`（会话 Cookie，没有 MaxAge），边缘对带 Cookie 的请求先换令牌、失败就答 `401 SESSION_ENDED`、不转发（`be-edge/edge.go:135-155`、`193-196`），连 `/api/iam/login`、`/callback` 也拦，静态站若挂了中间件连 index.html 都是 401：会话超时后再也登录不进来。改：FP15 写明路由与中间件的布局（`/` 不挂）；be-edge 答 `SESSION_ENDED` 时清掉 Cookie，或对登录与回调路径带 Cookie 也放行（线协议第 11 章加条款，P2）；L3 加“带已结束的 Cookie 去登录”。
- **M2** 一个标签页登出后，别的标签页的请求不带 Cookie，组件答 `TOKEN_INVALID` 而不是 `SESSION_ENDED`，FP06 只在后者跳登录；登出后浏览器状态（permissions、features、缓存、草稿）怎样清没写（协议 20 第 58、104 行，UI30）。改：外壳启动先取 `/api/features` 作登录门槛；写明 `TOKEN_INVALID` 的显示；BroadcastChannel 广播登出。
- **M3** 登出后跳 `/api/iam/login`，Casdoor 的会话还在，会静默再登录，共用终端登出无效（UI07、UI10）。改：登出后进外壳的“已登出”页；未决问题：对 Casdoor 发起登出或 `prompt=login`。
- **M4** FP05 新增“不要操作的本人路由”与 P8.7、易错点“注册没有操作定义的路由”冲突，没有决定记录；现成做法：D82 的固定“本人”段（`Kind: "self"`，视图里不需要授予，`authz/internal/view/view.go:268-287`），定义一个类似 `infra.authz.me.read` 的操作即可满足 P8.7，不动协议（代价：没有任何授予的用户不在视图里会被拒，前端要分清“没有任何权限”与 `AUTHORIZATION_UNPROVABLE`）。授权是槽位族：这条读取要进族的标准契约、用族级前缀，移动端与 bff 也用它。
- **M5** FP05 的结果与法人、维度无关，却要“切换法人时重取”；计算口径没写（要与成员执法同源：角色修订、任职绑定、治理单元上限、可用性、账号停用、只读续期）；取不到时菜单会被清空，违背协议 20 的“暂时无法证明不显示为无权”；只在登录、切换法人、403 时重取，违背“菜单权限的变化在运行时生效”。改：写明不按法人过滤（或加法人参数，要问维护者）；取失败保留上次或显示可重试；定时或窗口获得焦点时带 `BE-Polling` 重取，403 触发的重取要节流。
- **M6** 协议 20 要求页面模块声明“需要的能力”、`features` 带能力；FP02 没有能力，be-ops 的 features 只有 id 与 version；FP04 运行时只查组件、不查 `needs`；契约主版本从哪来没写。改：FP02 加 `capabilities`，FP04 查 `component` 加全部 `needs`；写明契约主版本的来源；be-ops 的 features 补能力（P2），之前首批不按能力过滤；`/api/features` 不可用时菜单怎样处理。
- **M7** FP03 按客户基线构建不同产物，FP15 却是一个组件一个镜像：同一版本对不同基线出不同镜像，与“版本号不复用、构建跳过已有镜像”冲突；品牌在构建时注入，而技术栈说是部署配置。改：定下谁、在哪、用哪个基线构建（例如装配项目的 `brickkit build` 把项目的 `brickkit.yaml` 作构建参数、镜像标签带基线摘要，或发布的镜像是标准基线、客户 Fork 自己构建）；品牌改为运行时读的部署配置（静态服务注入 `config.json`），补水印与灰度模式。
- **M8** 协议 20 整节没进设计：版本与旧客户端（UI15：构建版本、摘要命名的资源长期缓存、index.html 不缓存、最低客户端版本）；多语言与格式（UI16：页面不写字面文字并 lint、回退链、币种小数位、业务日期、法人时区、错误文本按 `reason` 与 `metadata`）；浏览器安全（UI17、UI18：CSP、AntDV v4 的 CSS-in-JS 与 `style-src`、富文本白名单、导出防公式注入、外部链接不由前端拼）；列表日期范围的默认值。
- **M9** FP08 少了：数据可能不完整（待办的 `stale`）、未知原因按保护处理、`Retry-After`、501 `CAPABILITY_UNSUPPORTED`、`IDEMPOTENCY_IN_PROGRESS`、`IDEMPOTENCY_KEY_REUSED`；审批决定的原因（P17.10：`VERSION_CONFLICT`、`TASK_NOT_PENDING`、`SELF_APPROVAL`、`NOT_ASSIGNEE`、`NOT_QUALIFIED`、`QUALIFICATION_UNKNOWN`、`REVISION_CHANGED`）没有显示方案、请求要带任务版本；只对带幂等键的请求自动重试（协议 20 第 51 行，UI31）没写。
- **M10** FP13 少了：保留 7 天、每用户 5 MiB；登出时清除或保留、共用终端上提交中与结果未确认的草稿连同幂等键保留（UI30）；“结果未确认 → 按幂等键查询”用哪个接口；受限字段怎样得知、资源定义可以声明允许进草稿。
- **M11** P1 要查清的 (b)(c)(d) 设计里没有结论：`IAM_CALLBACK_URL` 要是边缘来源加 `/api/iam/callback` 并登记在 Casdoor；`IAM_COOKIE_SECURE`、`IAM_AFTER_LOGIN_URL` 在格里与生产的取值；`return_to` 带路径与查询串、URL 编码、history 路由。
- **M12** 没有记录依赖版本（Node、pnpm、Vue、AntDV v4、vxe-table 与 vxe-pc-ui、ECharts、openapi-typescript、openapi-fetch、Vite、Vitest、静态服务的基础镜像：不能 scratch 或 distroless）；vxe-table 免费版能力逐项核对、记进 `ui-kit-pc` 的说明。

## 建议改

1. 跳转条件写成 `reason == SESSION_ENDED`，删“或令牌仍陈旧”（经边缘收不到 `TOKEN_STALE`）。
2. FP09 的动作入口：发之前校验形状 `/api/<名字>/flow/tasks/{id}/decisions`，或按组件 ID 自己推出（P17.14）。
3. 法人切换依赖 `mdm/org`，依赖表没有；写清切换是界面筛选还是安全 06 的“选定的任职”。
4. FP10 漏了收藏栏、“组织与法人”的组织部分、亮暗的“跟随系统”。
5. `packages/api` 用哪些契约版本、从哪取（`.brickkit/artifacts/`），怎样与基线对齐。
6. FP16：按协议 20 的验收清单与 UI01–UI31 标出由哪层测；lint 规则先放一个违规证明会红；FE-3 优先用无障碍树快照；两条验证故事对应哪条测试。
7. 轮询：页签隐藏时停；轮询收到 `SESSION_ENDED` 走同一条登录路径；features 与 permissions 的定时刷新带 `BE-Polling`。
8. 静态服务的缓存头（摘要资源 `immutable`、index.html `no-cache`）；SPA 回退排除 `/api/`。
9. FP05 的取舍注明移动端与 bff 也用。
10. 请求模式（普通、代理、扮演）怎样传，至少列进未决问题。

## 没能核实的

- T6 是否覆盖“带已结束的 Cookie 去登录”（M1 是读代码推出的）。
- 首批后端有没有按幂等键查结果的读取。
- SDK 在视图里找不到调用者时答 403 还是 404（关系到 M4 的 D82 式做法）。
- AntDV v4 的 CSS-in-JS 与严格 CSP 能否共存；静态服务选哪种。
- 协议 11 的列表默认范围的具体规则。
- 安全 06 的“请求模式”“选定的任职”在 SDK 里有没有对应的请求头。
