# 文档里的图：逐张处理（2026-10-25 起）

规则：[图与表](../../docs/zh/01-conventions/04-diagrams-and-tables.md#图放在哪里)。客户会读的文档保留图，图后写全它画的关系；开发与修改用的文档不放图，换成文字、表、编号步骤或角色表，图里有、正文没有的信息先补进文字再删图。完成后加检查。

## 分类

客户会读的，按[文档索引](../../docs/zh/README.md)与[总览](../../docs/zh/00-overview/README.md)的“向客户介绍”路线：产品、选择方式与客户组合、选型说明（`guides/`）、组件货架、业务流程（`08-flows/`）、运维手册。

| 文件 | 图 | 类 | 做法 | 状态 |
| --- | --- | --- | --- | --- |
| `00-overview/01-product.md` | 1 | 客户 | 保留，补“图中的关系” | 完成 |
| `00-overview/04-selection.md` | 3 | 客户 | 同上 | 完成 |
| `00-overview/guides/README.md` | 1 | 客户 | 同上 | 完成 |
| `00-overview/guides/analytics-and-reporting.md` | 1 | 客户 | 同上 | 完成 |
| `00-overview/guides/authorization.md` | 1 | 客户 | 同上 | 完成 |
| `00-overview/guides/business-and-channels.md` | 2 | 客户 | 同上 | 完成 |
| `00-overview/guides/files-and-attachments.md` | 1 | 客户 | 同上 | 完成 |
| `00-overview/guides/finance-and-settlement.md` | 4 | 客户 | 已补“图中的流向”（`5d5a10ca`），核对 | 完成 |
| `00-overview/guides/frontend.md` | 1 | 客户 | 保留，补“图中的关系” | 完成 |
| `00-overview/guides/identity.md` | 1 | 客户 | 同上 | 完成 |
| `00-overview/guides/supporting-capabilities.md` | 1 | 客户 | 同上 | 完成 |
| `08-flows/order-to-cash.md` | 1 | 客户 | 同上 | 完成 |
| `08-flows/procure-to-pay.md` | 1 | 客户 | 同上 | 完成 |
| `00-overview/02-domains-and-boundaries.md` | 3 | 开发 | 换成文字或表（总览里属于“设计与开发”路线） | 完成 |
| `00-overview/05-change-and-retirement.md` | 1 | 开发 | 同上 | 完成 |
| `00-overview/08-system-views.md` | 2 | 开发 | 上下文与容器换成表；“关键流程的时序图在哪里”改成“步骤与分支在哪里”（AI 定：不在客户路线里，客户看产品页的装配全景） | 完成 |
| `01-conventions/05-ai-navigation.md` | 1 | 开发 | 换 | 完成 |
| `04-foundations/01-deployment-and-runtime.md` | 2 | 开发 | 换 | 完成 |
| `04-foundations/03-transactions-and-messaging.md` | 1 | 开发 | 换 | 完成 |
| `04-foundations/06-message-transport.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/01-background-work.md` | 1 | 开发 | 换（时序 → 编号步骤与分支） | 完成 |
| `06-protocols/02-projections.md` | 2 | 开发 | 换 | 完成 |
| `06-protocols/03-audit-durability.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/04-order-reservation.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/05-billing-settlement-and-payment.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/06-period-close.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/09-approval-and-workflow.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/10-external-integration.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/11-tiering.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/12-attachments-and-object-storage.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/15-backup-and-recovery.md` | 3 | 开发 | 换 | 完成 |
| `06-protocols/16-go-live-and-import.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/20-frontend.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/security/06-security-contracts-and-capabilities.md` | 2 | 开发 | 换 | 完成 |
| `06-protocols/security/08-state-and-change-protocol.md` | 2 | 开发 | 换 | 完成 |
| `06-protocols/security/10-providers-and-member-switching.md` | 1 | 开发 | 换 | 完成 |
| `06-protocols/security/11-identity-member-switching.md` | 2 | 开发 | 换 | 完成 |
| 组件 `erp/sales` `docs/flows/confirmation.md`、`delivery-and-billing.md` | 2 | 开发 | 换；组件要升版本、发布 | 完成：`erp/sales` 3.0.7 |
| 组件 `erp/billing` `docs/flows/billing.md` | 1 | 开发 | 同上 | 完成：`erp/billing` 3.0.5（依赖 `erp/sales@3.0.7`） |

合计：`docs/zh/` 53 张（客户 19、开发 34），组件 3 张。

## 每张图的做法

1. 读图与它前后的正文，列出图里的每一条关系（谁把什么交给谁、哪条分支怎样处理、谁在谁之前）。
2. 开发文档：正文已有的不重复；没有的补进最合适的形式——流程写成编号步骤，分支与失败写进步骤下或一张表，结构与协作写成角色表或“上游 → 下游”的表；补齐后删图，图前“下图”之类的指向一起改。
3. 客户文档：图前一句说它回答什么，图后一节“图中的关系”逐条写出。
4. 改完跑 `make docs-check`（链接、锚点、表格）；指向被删的图的链接与锚点（例如系统视图的“时序图在哪里”）一起改。

## 收尾

- 加检查：开发用的目录（`01-conventions/`、`02-decisions/`、`04-foundations/`、`06-protocols/`、`07-components/`、总览里的开发页）不出现 Mermaid 块；客户读的文档里每个 Mermaid 块后面有“图中的关系”一节。先红再绿。
- 规范里“关键流程的时序图”的说法（系统视图、`04-diagrams-and-tables.md` 的相关段落）跟着改。
- 组件的 3 张随下一次组件发布处理，或单独发一个只改文档的版本。

## 结果（2026-10-25 完成）

- `docs/zh/` 开发文档的 34 张图换成编号步骤、表或一句话（`dc1cb321`）；被别处链接的小节标题保留，只有安全 11 的“时序图”改名为“主路径与失败分支”，唯一的入链（系统视图）同步改。系统视图的上下文与容器换成表，“关键流程的时序图”改为“步骤与分支在哪里”；规范、协议目录与总览索引里指向时序图的说法一起改。
- 客户读的 19 张图，每张后面补“图中的关系／流向”（财务指南 4 张原已补）。
- 组件的 3 张随只改文档的版本发布：`erp/sales` 3.0.7、`erp/billing` 3.0.5（依赖跟到 `erp/sales@3.0.7`），用 `brickkit release --notes-file`，Go 的 `v` 标签同一份说明。`erp/sales` 的 `v3.0.7` 是用 `git tag -F` 打的，`#` 开头的两行标题被当注释去掉（正文还在，已推送不改）；`erp/billing` 起加 `--cleanup=verbatim`。外壳 `be/go-core` 仍编进 3.0.6／3.0.4（彼此一致、代码未变），下次外壳发布时一起升。
- 检查 `infra/scripts/docs-diagrams.py`（`make docs-diagrams`，进 `make gates`）：先在组件的 3 张图上红，再各放一个嵌套目录里的违规（开发目录里的图、客户文档的图后没有关系）确认报出，删掉后全绿。
