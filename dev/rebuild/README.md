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

## 现在在哪里

- 设计冻结报告已确认（全部 AI 选择 A01–A98 确认；D70 补充；D75 首批范围），设计阶段的记录在 `archive/design-2026-10/work/`。
- 正式文档迁移按 [migration-plan.md](migration-plan.md) 进行。迁移中新增的 AI 选择 A99–A106 记在 `docs/zh/02-decisions/09-ai-choices.md`，A100–A106 用户 2026-10-15 全部确认。
- 之后：代表部署实验（D41），再按 [rebuild-plan.md](rebuild-plan.md) 重建。

## 任务结束时：知识库反馈

把知识库反馈作为一个 PR 提交（走 `kb-contribute`）。目前草稿有两项：

1. Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；知识库选主相关文档按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
2. 跨平台 D2 一节没有把 uni-app 列为 Vue 团队的 App 选项。
