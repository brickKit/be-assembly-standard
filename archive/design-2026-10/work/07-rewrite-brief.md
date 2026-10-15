# 终稿改写说明（给改写与对照的子 agent）

> 2026-10-15 建立。同日用户更正：文档由主会话自己写，子 agent 只做审查。所以本页现在是主会话写终稿时的清单，以及审查 agent 的规则（末节“对照说明”）。

## 你要做什么

把指定的草稿改写成**终稿**：每份只写最终做法，读者一次读懂；细节一条不丢。终稿写在 `tempDocs/final/` 下的指定位置。只写你被指定的终稿文件与一份改写报告；**不改任何其他文件**（草稿、工作记录、检查脚本、其他终稿都不动）。

## 终稿的写法

先读这三份终稿规范，照着写：

- `final/01-conventions/03-documentation.md`（尤其“写法”“语言”）
- `final/01-conventions/04-diagrams-and-tables.md`（图与表）
- 一份已完成的样例：`final/06-protocols/security/03-authorization-acceptance-and-revocation.md`（结构重组的写法）与 `final/06-protocols/security/04-authorization-administration-and-appointments.md`（保持结构的写法）

要点：

1. **细节一条不丢**：规则、参数、数字、条件、独立预期（编号与含义完全不变，整张表搬过去）、参考模型的结论（种子、运行次数、坏变体清单、检出次数、模型不覆盖的条款）、外部依据的链接、已知风险。合并、重排、改写措辞都可以；删掉或改变一条实质规则不行。
2. **去掉过程痕迹**：状态行（“状态：……候选，尚未冻结”）、“候选”“第几份候选”“按第 X 轮复查补充”“（2026-10-xx 按某某修正：……）”、问题与覆盖编号（I12、C40 等）、指向 `work/` 的链接（`work/checks/` 下的参考模型除外）、“下一步见接续清单”、旧实现的状态（“现行 SDK 已有……”“当前 `infra/authz` 已有”）。修正说明里若有仍然有效的规则，保留规则本身。“第几份候选”改成文档链接（例如“安全 08”）。
3. **决定编号保留**（D01–D74，可在 `work/02-decisions.md` 核对主题）。AI 选择编号（A01–A58）**不写进**终稿。
4. **骨架**：开头一段说明本页回答什么；正文；独立预期；参考模型（如有）；依据；末尾统一一节“已知风险与待定”（原来散在各处的“剩余”“尚未”“冻结前须……”收到这里，写明由什么实验或设计来定）。不是每份都要全部几节。
5. **一件事只写在一处**：别的文档已经完整写了的机制，这里一句话加链接。不要为了“完整”把别处的规则抄一遍。
6. **措辞**：中文；句子完整，主语明确；不要缩写成电报体（“须”“仅”“其”可以，但不要“A／B 档在先限定可”这种挤压）；斜杠“／”分隔的并列改写成“与”“或”“、”。代码标识符、参数名、事件名保持原样并加反引号。
7. **太长时**：超过约 350 行或明显覆盖几件独立的事，可以按主题拆成几份（同一目录下，文件名带原编号，例如 `09a-…`、`09b-…`），但**每个预期编号前缀只能在一份文档中**（检查 33 的规则）。拆分时在报告里说明理由。

## 图与表

按《图与表的规范》，在改写时补上**从正文能直接推出**的意图类图表：

- 文中有状态（实例、分支、认领、工作项、会话……）的对象：写**状态迁移表**（当前状态、事件、守卫、结果状态、动作、发出的事件）；正文已有的状态描述是唯一来源。
- 跨组件或跨步骤、且有失败分支的流程：写一张**带失败、超时、重复分支的时序图**（Mermaid），参与者用组件 ID 或文中的角色名；图后写一两句结论。
- 几个条件共同决定结果的规则：写**决策表**。

只画正文已经写明的内容。画图时发现正文缺了某个状态、转换或分支的规则，**不要自己补规则**，写进改写报告的“发现的问题”。不为了“有图”而画图；简单的规则不需要。

## 链接

- 终稿之间用相对路径互相链接。已整理成终稿的文档：`final/00-overview/`、`final/01-conventions/`、`final/04-foundations/`、`final/07-components/`、`final/06-protocols/14-data-foundations.md`、`final/06-protocols/security/`（README 与 01–05，以及本批已完成的）。
- 尚未整理的草稿用指向草稿的相对路径（从 `final/06-protocols/security/` 出发是 `../../../security/…`、`../../../protocols/…`；从 `final/06-protocols/` 出发是 `../../security/…`、`../../protocols/…`）。主会话会在草稿整理后统一改链接。
- 草稿里指向正文 00–09（`../00-project-overview.md` 等）、`components/`、`replacements/`、`validation/`、`07-validation.md` 的链接，改指向对应终稿：正文 01 → `final/00-overview/02-domains-and-boundaries.md`；正文 02 → `final/06-protocols/security/README.md`；正文 03 → `final/04-foundations/01-deployment-and-runtime.md`；正文 04 → `final/04-foundations/02-data-and-lifecycle.md`；正文 05 → `final/04-foundations/03-transactions-and-messaging.md`；正文 06 → `final/01-conventions/01-engineering.md`；正文 07 → `final/01-conventions/02-testing-and-validation.md`；正文 08 → `final/00-overview/06-roadmap.md`；正文 09 → `final/04-foundations/README.md`；`components/<领域>.md` → `final/07-components/<领域>.md`；`components/catalog.md` → `final/00-overview/03-catalog.md`；`components/selection-map.md` → `final/00-overview/04-selection.md`；`replacements/<名>.md` → `final/00-overview/guides/<名>.md`（消息、数据与存储、运行与部署三篇已并入 `final/04-foundations/` 的对应文件）；`validation/*.md` → `final/01-conventions/validation/*.md`。锚点按目标文件的实际标题核对（标题转锚点：去掉标点，空格变 `-`，英文小写）。

## 改写报告

写到 `work/rewrite-reports/<终稿文件名>.md`（目录不存在就建），内容：

1. 来源去向：草稿的每一节去了终稿的哪一节。
2. 有意去掉的内容（只列过程痕迹以外的；过程痕迹不用列）。
3. 新增的图与表，以及它们依据的正文段落。
4. 发现的问题：正文内部矛盾、与其他文档冲突、画图时发现的缺口、无法确定含义的句子。每条写清楚位置与理由。**不要自己裁定**，主会话处理。
5. 拆分（如有）的理由。

完成后用几句话回复：写了哪些文件、报告在哪、最重要的发现。

## 对照说明（给对照 agent）

你只读不写（除了你的对照报告）。逐句对照指定的草稿与终稿，找出：

1. 草稿中的实质内容（规则、参数、数字、条件、预期编号与含义、参考模型的结论、外部依据）在终稿中缺失或含义改变；
2. 终稿中没有出处的新规则（图与表若只是正文的另一种写法，不算新规则；改写报告中已列明、由主会话裁定的修改见 `work/08-reorg-findings.md`，不算错误，但要核对改动是否与裁定一致）；
3. 终稿与其他终稿的矛盾。

去掉过程痕迹（状态行、“候选”、问题编号、工作记录链接、旧实现状态）是有意的，不要报告。只是措辞或顺序的改变，不要报告。

报告写到 `work/rewrite-reports/review-<批次>.md`：每组来源与终稿一节，逐条写“草稿原句（简短引用）→ 终稿缺失或改变的情况 → 建议放在哪里”；完整的一组写一行“完整”。最后单列“与其他文档的矛盾”。回复时用中文概括最重要的几条。
