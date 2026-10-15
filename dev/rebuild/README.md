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

## 现在在哪里

- 设计冻结报告已确认（全部 AI 选择 A01–A98 确认；D70 补充；D75 首批范围），设计阶段的记录在 `archive/design-2026-10/work/`。
- 正式文档迁移已完成（[migration-plan.md](migration-plan.md)）。迁移中新增的 AI 选择 A99–A106 记在 `docs/zh/02-decisions/09-ai-choices.md`，A100–A106 用户 2026-10-15 全部确认。
- 之后：代表部署实验（D41），再按 [rebuild-plan.md](rebuild-plan.md) 重建。

## 下一步：代表部署实验（D41）的实施计划

2026-10-15 正式文档迁移全部完成并推送（检查全过，30 个参考模型通过，复查 29 条已修，AI 路由测试 87/90 过关，A100–A106 用户确认）。用户随后同意了实验计划的方向，下一步是**起草实验计划交用户审**（文档要求：实验的具体计划写在重建计划中，经用户确认后执行；动仓库的每一步先列动作请用户确认，改名除外）。

已同意的方向（起草时细化，不当作已定的细节）：

- **业务链**：报价 → 订单确认与预占 → 出库 → 出账。
- **组件**：这条链的业务组件，加身份、授权、审计、伙伴、产品、组织等必需的支撑组件，大约 8–10 个，另加一个 Go 外壳。按边界卡的必需依赖求闭包确定（检查 34）。
- **最小条件**：Go SDK 先做实验用得到的组件协议子集（D75）；`be-acceptance` 补验证这些组件所需的最少检查。
- **对照**：按[测试与验证的代表部署对照实验](../../docs/zh/01-conventions/02-testing-and-validation.md#代表部署对照实验)：单跑、外壳、混合 × Docker、Podman；两个额外对照组（连接池代理、只用 PostgreSQL）；整套 4 GiB 与 6 GiB 两个内存预算；收敛顺序与要比较的证据照该节。
- **计划要写清**：代表组件与业务链、SDK 先做到什么程度、每一步的改动与耗时预算、要动哪些仓库（按 [rebuild-plan.md](rebuild-plan.md) 的复用与 `legacy/` 分支规则）、产出的报告格式。

2026-10-16 已起草：[experiment-plan.md](experiment-plan.md)，待用户审。

## 任务结束时：知识库反馈

把知识库反馈作为一个 PR 提交（走 `kb-contribute`）。目前草稿有三项：

1. Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；知识库选主相关文档按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
2. 跨平台 D2 一节没有把 uni-app 列为 Vue 团队的 App 选项。
3. 项目文档“用什么方式表达”缺一处总的选择：14.04.03 只在图与表之间选；编号步骤（14.04 的操作手册、07 技术写作的一行）、填好的样例（只在 API 文档 D4）、改前改后的对比（只在知识库自己的写作规则 meta/02-writing）散在各处。建议在 14.04.03 D1 前加一张“内容的形状 → 图、表、代码、步骤、样例、文字”的表，写明这些都是按情况选的选项，同样适用于项目文档；“能用图代替的不写代码”放到项目文档里偏绝对，几行代码更直接的地方（接口形状、机制本身）应当用代码。本项目的写法见 `docs/zh/01-conventions/04-diagrams-and-tables.md` 的“先选表达方式”。
