# 重建阶段的工作区

> 2026-10-15 建立：终局设计已冻结并迁成正式文档（`docs/zh/`），设计阶段的工作区归档在 `archive/design-2026-10/`。本目录放重建阶段仍在进行的工作；工作结束后整体归档。

## 这里有什么

| 文件 | 内容 |
| --- | --- |
| [migration-plan.md](migration-plan.md) | 正式文档迁移的动作与进度（协议 21） |
| [migration-map.md](migration-map.md) | 承接表：旧文档每一节的去处 |
| [be-protocol-carry.md](be-protocol-carry.md) | 线协议细节的承接清单，重建 `be-protocol` 时逐条重审写入 |
| [rebuild-plan.md](rebuild-plan.md) | 仓库复用、`legacy/` 分支、改名与新建的清单与顺序；每一步动仓库前先列动作请用户确认（改名除外） |
| [implementation-checks.md](implementation-checks.md) | 冻结时列出、交给实现阶段核对的项 |
| [experiment-plan.md](experiment-plan.md) | 代表部署实验（D41）的实施计划（待用户审） |
| [step1-repo-actions.md](step1-repo-actions.md) | 实验第 1 步的仓库动作清单与执行结果（2026-10-17 已执行） |
| [step2-plan.md](step2-plan.md) | 实验第 2 步（`be-protocol` 子集与 Go SDK）的任务、取舍与进度 |

## 现在在哪里

- 设计冻结、正式文档迁移已完成（[migration-plan.md](migration-plan.md)）；AI 选择 A99–A110 记在 `docs/zh/02-decisions/09-ai-choices.md`（A109 驻留期起始值待复核，其余已确认）。
- **代表部署实验（D41）进行中**：计划 [experiment-plan.md](experiment-plan.md) 用户 2026-10-16 说“开始”，按计划执行；当前在**第 0 步**（机制验证，不动远端仓库）。档案在 [experiment-records/](experiment-records/README.md)，原始输出在 `experiment-data/`。
- 实验之后先做底层（权限、登录、冷热数据、事务、消息），再按 [rebuild-plan.md](rebuild-plan.md) 重建业务组件。

## 2026-10-16 会话结束时的交接

**已定（这次会话）**：

| 项 | 结论 | 记在 |
| --- | --- | --- |
| 版本号 | 全部仓库从 `3.0.0` 起，`X` 大版本、`Y` 阶段性变化（新功能、从开发进入正式）、`Z` 修复；不重用旧号、旧标签保留、不需要 `GOPRIVATE`；Go 模块路径带 `/v3`（Go 的硬规定） | A110（取代 A107）；开发流程的版本一节 |
| TypeScript | 当前范围不做；`infra/bff-mobile` 用 Go（gqlgen） | A108 |
| 冷热分层 | 底层阶段完整实现；驻留期按数据类别（起始 12 个月等） | D75 修订；协议 11；A109（待复核） |
| 实验矩阵 | 6 形态 × 3 拓扑打底，五套测试（A 矩阵、B 对照、C 故障、D 多版本、E 多实例多库）；正确性先于性能；工时不限，一项项测、测完一项记一项 | experiment-plan.md |
| `mode: local` | BrickKit 回复不做长期运行的本机部署；本机进程三行只量资源与通信，标“不推荐”（图省事的另类模式） | FRR-001 已关闭（v1.4.2 复测通过） |
| `local` 之后的用法 | 全部部署形态测完后本项目基本不再用 `local`，用 Docker 或 Podman（按结果定）；给 BrickKit 的部署形态反馈预定在第 14 步一次发出，中途不发（用户 2026-10-17） | experiment-plan.md 的“给 BrickKit 的部署形态反馈（预定）” |
| 记录方式 | 档案（给 AI，详细、先结论、表格优先）+ 报告（给用户，含“用什么测的”与额外发现的表）+ 原始数据 | experiment-plan.md 的“记录与报告” |
| BrickKit CLI | 项目要求升到 v1.8.1（2026-10-17；项目技能同步更新）。v1.6.0 起只写 `deployment.image` 的组件来自本地源也拉取，要在本机构建的组件必须写 `deployment.build` | `infra/scripts/lib/require-brickkit.sh` |

**第 0 步的进度**：

| 编号 | 项 | 状态 |
| --- | --- | --- |
| 0-01 | `GOPRIVATE` 绕过 Go 代理与校验和库 | 完成；因 A110 已不需要，留作历史 |
| 0-02 | 同号重发与 BrickKit 两层缓存 | 完成；缓存会静默给出旧内容；v1.5.0 起报 `VERSION_CHANGED`（FRR-002 复测通过） |
| 0-03 | 一个仓库放多个组件（探针） | 完成；v1.5.0 起安装源可写 `repo`，探针用 `brickkit add` 加入，不再手写三层（FRR-003 复测通过） |
| 0-04 | Go 外壳承载成员（外壳自己的 `go.mod` 引入成员模块；BrickKit 只核对成员版本，不替外壳编译）；成员版本不一致时被拒 | 完成（2026-10-17）；“编进的代码与声明不符”只有启动器能拦，第 2 步的启动器按 Go 构建信息核对；按标签取成员留到第 4 步；v1.6.0、v1.6.1 复测通过（FRR-004、FRB-001） |
| 0-05 | 全部组件与外壳 `mode: local`（`target: docker`，基础资源在 Docker） | 完成（2026-10-17）；Go、Python 的单跑与外壳都能跑，看护行为与文档一致；v1.7.1 起单跑的本机进程与本机外壳的成员都用 `local.migrationCommand` 从源码迁移；`go run` 常驻，内存分开报；计划的“负载与测量”已补三条 |
| 0-06 | 本机进程与 Podman 混合 | 完成（2026-10-17）；全部容器、外壳在容器、外壳在本机三种布局都通；无根 Podman 的 `host-gateway` 可用；正式跑 P、LP 行时基础资源只起 Podman 那套 |
| 0-07 | minikube 跑 BrickKit 生成的 K8s 清单（含外壳）；`local`、`debug` 不能配 `k8s` | 完成（2026-10-17）；v1.7.2 起外壳成员的地址写成员自己的服务名，K8s 上调用链通（FRB-004 关闭）。镜像要 `minikube image load`；没有 kubectl，用转给 `minikube kubectl --` 的小脚本 |
| 0-08 | 同一组件两个版本并存（BrickKit 多版本共存：`requiredBy`） | 完成（2026-10-17）；`add` 自动保留兼容版本，外壳只编进一个版本、另一个单独运行；迁移按版本串行；迁移顺序保护有效 |
| 0-09 | 同一组件两个副本 | 完成（2026-10-17）；K8s 上通过；v1.8.0 起 Docker、Podman 也支持副本（FRR-006 关闭），套件 E 恢复四格；Go、Python SDK 都要做到删副本时零失败 |
| 0-10 | 两个 PostgreSQL 实例 | 完成（2026-10-17）；分实例完全靠配置覆盖；三种形态下连接与迁移都去对的实例；特殊字符的密码三条注入路径一致 |
| 0-11 | Podman 有根与无根 | 完成（2026-10-17，用户执行有根脚本）；有根下 BrickKit 正常，但与同机 Docker 冲突、容器之间不通（静默）；B6 要在没有 Docker 的条件下跑；每格先跑冒烟测试 |
| 0-12 | 连接池代理的事务模式与 `SET LOCAL`（以及 pgx 的预编译语句） | 完成（2026-10-17）；设计依赖的事务内设置都成立；pgx 默认模式要求 PgBouncer 开 `max_prepared_statements`（记进交实现核对的项） |
| 0-13 | 负载与数据的试跑规模 | 推迟到有业务组件之后（第 8 步前） |

**第 0 步与第 1 步已完成**（2026-10-17）：0-01 到 0-12 完成，0-13 按计划推迟；第 1 步的仓库动作已执行（[step1-repo-actions.md](step1-repo-actions.md)）。**正在做第 2 步**：`be-protocol` 的实验子集与 Go SDK，任务与进度在 [step2-plan.md](step2-plan.md)。

2026-10-17 起连续推进（用户授权）：每项做完写记录、更新本文件、提交，直接做下一项；只在需要用户决定、需要 BrickKit 配合、对外难撤回的动作（第 1 步的仓库动作先列清单请用户确认；首次推送或发布标签）时停下。

**未推送的提交**：`main` 比 `origin/main` 多若干提交（从 7aad7d4 起），用户没有要求推送；以 `git log origin/main..main` 为准。

**已知、暂不处理**：`infra/scripts/tests/test_ship_dryrun.sh` 失败——旧的 `ship.sh` 还调用旧 `be-acceptance` 的命令，迁移后已不存在；发布工具随重建重新提供，届时一并处理。

**给 BrickKit 的收件箱** `brickkit-feedback/rebuild.md`：FRR-001 到 FRR-006、FRB-001 到 FRB-005 全部关闭（最后一次复测 2026-10-17，v1.8.1）；没有未回复的条目。

## 任务结束时：知识库反馈

把知识库反馈作为一个 PR 提交（走 `kb-contribute`）。目前草稿有三项：

1. Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；知识库选主相关文档按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
2. 跨平台 D2 一节没有把 uni-app 列为 Vue 团队的 App 选项。
3. 项目文档“用什么方式表达”缺一处总的选择：14.04.03 只在图与表之间选；编号步骤（14.04 的操作手册、07 技术写作的一行）、填好的样例（只在 API 文档 D4）、改前改后的对比（只在知识库自己的写作规则 meta/02-writing）散在各处。建议在 14.04.03 D1 前加一张“内容的形状 → 图、表、代码、步骤、样例、文字”的表，写明这些都是按情况选的选项，同样适用于项目文档；“能用图代替的不写代码”放到项目文档里偏绝对，几行代码更直接的地方（接口形状、机制本身）应当用代码。本项目的写法见 `docs/zh/01-conventions/04-diagrams-and-tables.md` 的“先选表达方式”。
