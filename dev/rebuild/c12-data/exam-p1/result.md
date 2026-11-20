# C12 P1 设计考试的处理

答卷：[answer.md](answer.md)。设计：`components/frontend/pc/docs/design.md`（处理后 FP01–FP20）。2026-11-20。

## 先核实的

- **SDK 在视图里找不到调用者时答什么**（关系到 M4）：`guard.go` 的准入照常通过（`Lookup` 对不在分片里的主体给空段，安全版本 0 不算陈旧）；处理函数里 `authz.Subject.Check` 用空段求值，答 `PERMISSION_DENIED`（403）；视图过期答 `AUTHORIZATION_VIEW_EXPIRED`（503）。所以 D82 式的本人段走得通。实现时发现：没有段时 `Check` 先判可见性，答的是 `NOT_FOUND`（404）而不是 403；授权组件的处理函数把这两种拒绝都答成 200 与空集（`infra/authz` 3.0.60），前端不用分辨（FP05）。授权组件的 `holders` 把每条授予的被授予者与管理持有人都算作持有者（`authz/internal/view/view.go:70-96`），所以有任何授予的用户都有这个段。
- **M1**：读 `be-edge/edge.go` 的 `ServeHTTP`，带 Cookie 的请求先换令牌、`SESSION_ENDED` 就答 401、不转发，登录与回调路径没有例外；身份成员的登录不看旧 Cookie（`iam-casdoor/internal/login/login.go`）。成立。
- **“按幂等键查询”用哪个接口**（M10）：SDK 的 `idem.Do` 对同一键、同一请求原样返回原结果（`replayed`），先到的还没提交时答 `IDEMPOTENCY_IN_PROGRESS`。查询就是用同一个键重发同一个请求，不需要另开读取。
- **列表默认范围**：协议 11，“未关闭，或最近 N 天内创建”，N 起始 90 天，由属主套用。
- **能力**：协议 20 的“需要的能力”取自安全 09b 的能力目录（授权成员的能力）；首批的页面模块都不需要；be-ops 的 `features` 只有组件与版本。

## 逐条

| 意见 | 处理 |
| --- | --- |
| M1 | FP06 写明边缘的布局（`/` 不挂中间件）；P2 给 be-edge 与线协议第 11 章补两条：答 `SESSION_ENDED` 时清掉会话 Cookie；身份成员的登录与回调路径带 Cookie 也照公开路由转发；P3 的 L3 加“带已结束的 Cookie 去登录” |
| M2 | FP06：登录门槛（启动先取 `features`）；`TOKEN_INVALID` 与 `SESSION_ENDED` 都走“需要登录”；`BroadcastChannel` 广播登出；登出清掉的浏览器状态与例外 |
| M3 | FP06 与边界表：登出后进“已登出”页；不被静默再登录是身份成员的义务，P2 给 `iam-casdoor` 补（先核实 Casdoor 支持结束会话还是 `prompt=login`） |
| M4 | FP05 改成 D82 式本人段与一条普通的声明操作，不动线协议；进授权槽位族的标准契约；没有任何授予的答空集、503 保留上次 |
| M5 | FP05 写明计算口径与视图同源、不按法人筛、切换法人不重取；取失败保留上次；每 5 分钟与获得焦点时带 `BE-Polling` 重取，403 触发的重取 30 秒最多一次 |
| M6 | FP02 加 `capabilities`、`contract` 的来源；FP04 查 `component` 加全部 `needs`，`features` 带能力后再查能力；`features` 不可用时的处理；be-ops 的能力列进未决问题（首批没有需要能力的模块，不放 P2） |
| M7 | FP03 改成基线是源码的一部分（像外壳的成员清单），一个版本一个镜像；客户基线不同就 Fork；FP11、FP15 品牌改为运行时的 `/config.json`，补水印与灰度；取舍写理由。**AI 定，待复核** |
| M8 | 新增 FP17（多语言与格式）、FP18（列表默认范围）、FP19（版本与旧客户端）、FP20（浏览器安全：内容安全策略、内联样式的理由、富文本、导出、外部链接）；最低客户端版本的后端声明列进未决问题 |
| M9 | FP08 补全原因：不可证明、`Retry-After`、501、`IDEMPOTENCY_IN_PROGRESS`、`IDEMPOTENCY_KEY_REUSED`、数据可能不完整、不认识的按保护处理；FP09 补审批决定的原因与任务版本；FP07 只自动重试带键的请求 |
| M10 | FP13 补保留 7 天、5 MiB、登出时的保留与清除、提交中的草稿与键、按白名单存字段；查询结果用同一个键重发 |
| M11 | “依赖”补部署的配置：`IAM_CALLBACK_URL`、`IAM_AFTER_LOGIN_URL`、`IAM_COOKIE_SECURE` 在格里与生产的取值；FP06 写 `return_to` 的编码与身份成员接受的形状 |
| M12 | “依赖”补工具与库的版本表（2026-11-20 查的稳定版本），TypeScript 7 与 `vue-tsc` 3 能否一起用在 P4 实测；vxe-table 免费版的核对放进 `ui-kit-pc` 的说明；静态服务用 nginx 非特权 Alpine 镜像 |
| 建议 1 | FP06 只按 `SESSION_ENDED`、`TOKEN_INVALID` 跳，写明经边缘收不到 `TOKEN_STALE` |
| 建议 2 | FP09 由发布组件推出决定入口，不读投影 |
| 建议 3 | FP10 与依赖表：`mdm/org` 可选；切换法人只是界面筛选，不是选定的任职 |
| 建议 4 | FP10、FP11 补收藏栏、组织、跟随系统 |
| 建议 5 | FP07 写契约从基线里的精确版本取、提交进仓库、检查核对 |
| 建议 6 | FP16 补 UI01–UI31 由哪层守住、lint 先证明会红、FE-3 用无障碍树快照、两条验证故事 |
| 建议 7 | FP06：页签隐藏时停轮询；轮询收到 401 走同一条路径；定时刷新带 `BE-Polling` |
| 建议 8 | FP15、FP19：缓存头、history 回退排除 `/api/` |
| 建议 9 | FP05 写明移动端与 bff 也用 |
| 建议 10 | 未决问题：请求模式与选定的任职 |

## 没能核实、留到实现时测的

- Ant Design Vue v4 在 FP20 的内容安全策略下是否不报违规（P4 实测）。
- TypeScript 7 与 `vue-tsc` 3.3 能否一起用（P4 实测）。
- Casdoor 结束会话的方式（P2 核实）。
