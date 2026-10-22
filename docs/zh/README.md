# BrickEnterprise 文档

本目录是项目的正式文档：每份只写现在成立的做法，修改经过在 Git 中。开发完成之前只写中文（D67），结构为多语言留了位置。进入项目先读根目录的 `AGENTS.md`：它按任务把你路由到这里的具体文件。

## 目录

| 目录 | 内容 |
| --- | --- |
| [00-overview/](00-overview/README.md) | 产品、领域与边界、组件全景与货架、选择关系与客户组合、变更与停用、路线、术语表、系统视图、组件索引（生成）、选型说明 |
| [01-conventions/](01-conventions/README.md) | 开发与维护的规则：工程规范、测试与验证（含验收矩阵）、文档、图与表、AI 导航、组件实现、种子与测试数据、参考实现、AI 编码习惯、开发流程与发布、改动配方 |
| [02-decisions/](02-decisions/README.md) | 决定记录：维护者的前提、决定（D 编号）、AI 选择（A 编号）、原有决定（0101–0509）的承接 |
| [03-seed-data.md](03-seed-data.md) | 种子数据清单与测试账号 |
| [04-foundations/](04-foundations/README.md) | 底层选择：跨方面的取舍，以及数据库、消息运输、组件协议与语言、调用与错误、边缘、观测、前端各一篇 |
| [05-operations/](05-operations/README.md) | 运维手册：备份与恢复、升级与维护窗口、告警与处置、客户上线 |
| [06-protocols/](06-protocols/README.md) | 安全 01–11（[security/](06-protocols/security/README.md)）与协议 01–21：跨组件的规则、状态与独立预期 |
| [07-components/](07-components/README.md) | 组件边界卡 |
| [08-flows/](08-flows/README.md) | 端到端的业务流程：步骤、组件与衔接方式 |

## 两条阅读路线

- **了解项目、向客户介绍**：产品 → 组件全景 → 选择方式与客户组合 → 选型说明（[总览](00-overview/README.md)）。
- **开发与修改**：根 `AGENTS.md` 的路由表 → 相应的规范或协议 → 组件仓库的 `AGENTS.md` 与 `docs/design.md`。规则冲突时，决定记录优先于规范，规范优先于单个组件的约定。

参考模型与文档检查在 `be-acceptance` 仓库（检出在 `tools/be-acceptance/`）；组件必须遵守的规则在重建 `be-protocol` 时从安全与协议中抽出（A99）。
