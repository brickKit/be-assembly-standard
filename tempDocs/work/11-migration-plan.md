# 正式文档迁移计划（协议 21）

> 2026-10-15 用户确认动作清单（“A”）。按[协议 21 的正式文档迁移](../final/06-protocols/21-verification-and-migration.md#正式文档迁移)执行；本页记动作与进度，承接表在 [12-migration-map.md](12-migration-map.md)。

## 已确认的做法

- 参考模型与文档检查脚本放进 `be-acceptance`（用户选 A）：`stage-b` 当前提交建为 `legacy/v1` 并推送；`main` 从零开始，只放 `models/` 与 `doc-checks/`，标签 `2.0.0`；根项目子模块指针改到新 `main` 并提交；正文用相对路径链接；旧 `make gates` 中的九个 Go 门禁随旧代码退出（D59），从 `Makefile` 移除。
- 规则正文本次全部留在 `docs/zh/06-protocols`；重建 `be-protocol` 时再抽出“必须、应当、内部”的规则，`06-protocols` 改为引用（AI 选择，记 A99）。
- 安全 08 不拆（改变清单原定的拆分）：生效点表与安全处置、受保护操作、管理员恢复互相引用，拆开后多数任务要两份一起读；预期前缀 CP 也只能属于一份文档（检查 33 的 ONE_OWNER）。改为在开头加“按任务读哪几节”，115 条预期按十个主题分组，编号不变。
- 子 agent 只用于检查，且少开；承接表之后的工作由主会话依次做（用户 2026-10-15）。
- 仍在进行的工作文件（重建计划、交接、知识库反馈草稿、交实现验证清单）挪到 `dev/rebuild/`，不归档。
- 归档位置：旧正式文档 → `archive/docs-v2/`；`tempDocs/` 其余部分 → `archive/design-2026-10/`。`archive/pre-v1`、`brickkit-feedback/` 与 `dev/` 的其余部分不动。

## 步骤与进度

| 步 | 内容 | 状态 |
| --- | --- | --- |
| 1 | 承接表：旧 `docs/`、根 `AGENTS.md`、`README.md`、`.claude/skills/version-bump-ship`、`Makefile` 与文档检查的每一节写明去处 | 进行中 |
| 2 | 从开发区提取：AI 选择 A01–A99 写成 `02-decisions/09-ai-choices.md`（已完成）；39 条原有决定按原编号写进主题文件；证据摘要并入依据；冻结报告六至八节逐条对照（第六节的机制风险已补进各文档的“已知风险与待定”；第七节转入 `dev/rebuild/`；第八节即 D75） | 进行中 |
| 3 | 写正文：`final/` 用 `git mv` 搬到 `docs/zh/`；安全 08 加任务导航并分组预期（已完成）；协议 05 的预期分组（已完成）；去掉过程性说明；按承接表补写新内容 | 进行中 |
| 4 | `be-acceptance`：挪分支、新 `main`、放入模型与检查、改链接 | 待做 |
| 5 | 归档旧文档与 `tempDocs/`；工作文件挪到 `dev/rebuild/` | 待做 |
| 6 | 入口与工具：根 `AGENTS.md`、`README.md` 中文重写；技能链接；`Makefile`（`docs-mirror` 移出 `gates`，`docs-boundary` 禁止 `tempDocs`，新增 `docs-links`、`docs-ids`、`docs-closure`、`design-models`） | 待做 |
| 7 | 收尾检查与两路复查；分批提交 | 待做 |
