[English](../en/README.md) · [中文](README.md)

# be-assembly-standard 文档

本仓库的项目级文档，中文版。每个文件夹或文件前面的编号就是阅读顺序。英文文档在 `docs/en/`，是主文件；本树与它逐文件对应：路径相同、文件名相同、`##` 小节相同，所以两份文档之间的链接在两棵树里是同一段文字。

入口是仓库根目录的 [`AGENTS.zh.md`](../../AGENTS.zh.md)（给 AI 助手）或 [`README.zh.md`](../../README.zh.md)（给人）；它们说明做什么事该打开哪份文档。组件自己的文档（`BRICKKIT.md`、`AGENTS.md`、`README.md`、`docs/`）放在组件目录里，沿用 brickKit 的 `.zh.md` 后缀规则。

## 目录

| 编号 | 文件夹或文件 | 放什么 |
|---|---|---|
| 01 | [约定](01-conventions/README.md) | 每个组件、外壳和工具都遵守的规则：开发流程、后端、前端、配置、数据、测试、登记表、文档、AI 尺度的代码、参考实现 |
| 02 | [决策](02-decisions/README.md) | 项目为什么是现在这个样子、哪些事不要再提，分在四个主题文件夹里：架构、权限、契约与数据、前端 |
| 03 | [种子数据](03-seed-data.md) | 演示数据、测试账号、怎么登录 |
| 04 | [底层选择](04-foundations/README.md) | 组件下面的每一块为什么是现在这样，每个关键选择一篇：数据库、标识、时间与金额、事务、事件、调用、后台任务、身份、授权、可观测性、配置、外壳；端口表，以及怎么更换实现 |

## 阅读顺序

1. **开始做一个组件**：先读[开发流程](01-conventions/01-development-workflow.md)，再读你要写的那一类的约定（[后端](01-conventions/02-backend.md)、[前端](01-conventions/03-frontend.md)），然后是[测试](01-conventions/06-testing.md)。
2. **提议改变项目的做法之前**：先看[决策索引](02-decisions/README.md)。决策优先于约定。
3. **想看跑起来的系统**：[种子数据](03-seed-data.md)。
4. **改 SDK、外壳或基础设施之前，或者提议替换其中某一块时**（"用 Kafka"、"支持数据库 Y"、"加个缓存"）：先看[底层选择索引](04-foundations/README.md)，再看那一块的文档。
