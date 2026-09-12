# BrickEnterprise 文档地图

> **先确认你是谁，再读那一行。** 读错入口比不读更费时间——设计书 3400 行，部署人员一行都不用看。

| 你是 | 你要回答的问题 | 从这里开始 |
|---|---|---|
| **AI 助手** | 这个仓库的规矩、禁令、我该查哪一节 | 仓库根 [`AGENTS.md`](../AGENTS.md)（每次会话自动加载）→ 它的**路由表** |
| **部署人员** | 装什么、什么顺序、哪些自动哪些要我做、报错了怎么办 | [`ops/部署手册.md`](ops/部署手册.md) ⭐ **只需要这一份** |
| **开发者**（写组件的人） | 怎么写一个组件、测试写在哪一层、卡住了怎么办 | [`standards/00-master-guide.md`](standards/00-master-guide.md) 的 **§4 SOP-W** → 该组件的 [`design/<仓库名>.md`](design/)；**测试怎么分层/怎么跑/卡住了怎么办**，唯一真相源是 [`standards/04-testing-standard.md`](standards/04-testing-standard.md)；**种子数据/测试数据怎么设计、组件间数据怎么协作**，唯一真相源是 [`standards/05-data-construction-standard.md`](standards/05-data-construction-standard.md)；「这个坑是不是已经踩过了」先查 [`dev/field-tested-pitfalls-log.md`](dev/field-tested-pitfalls-log.md)；日常怎么聚焦到几个组件、提交前要注意什么见 [`arsenal-maintenance-handbook.md`](arsenal-maintenance-handbook.md) |
| **架构 / 拿决策的人** | 为什么是这个形状、某条约束的出处 | [`../BrickEnterprise 设计书.md`](../BrickEnterprise%20设计书.md) —— **规范真相源** |
| **二次开发的客户工程师** | 我能改哪里、改了会不会被升级覆盖 | 该组件仓库的 `docs/手册.md` + `assembly.yaml` 的 `customization_guide` |
| **客户 / 主管理员** | 系统能做什么、我买了哪些模块、怎么用 | 🔜 **还没有**。现在一个业务组件都还没建，写了也是空的（见下方「什么时候写」） |

---

## 理论层 vs 操作层

这套文档刻意分成两层，因为它们**过期的速度不一样**：

| | 理论层 | 操作层 |
|---|---|---|
| 是什么 | 设计书、总纲、组件设计计划 | 部署手册、阶段计划、组件 README / 手册 |
| 回答 | **为什么**是这个形状 | **怎么**做这一步 |
| 谁改它 | 发现设计错了的人（**先改它，再改代码**） | 实际跑过一遍、发现和写的不一样的人 |
| 过期的样子 | 说的和代码不一致 | 照着做跑不通 |

**冲突时的优先级**：设计书 > 总纲 > 阶段计划 > `AGENTS.md`。
**但操作层跑不通时，不要迁就理论层**——先让它跑通，再回头判断是理论错了还是实现错了，然后**把结论写回去**。

**文档本身该怎么组织、什么时候该拆成独立文件、组件文档要同时服务哪两种读者**，规则见 [`standards/01-documentation-standard.md`](standards/01-documentation-standard.md)（英文正本，中文版 [`zh/standards/01-documentation-standard.md`](zh/standards/01-documentation-standard.md)）。

---

## 所有文档都可以改，包括推倒重写

这不是客套话，是这套文档的设计前提：

- **理论层是在「一个组件都还没写」的时候做出来的**（设计书决策 104 就是这么说的）。实现反馈一定会推翻其中一部分。
- **发现某一节和现实差太远，改它；发现整份的框架错了，重写它。** 不需要为了「保持一致」去将就一个已经错了的结构。
- 唯一的纪律是**顺序**：先改文档、再改代码。反过来做，文档一周内就失真，然后所有人都不再看它。
- 另有三张表是例外，**只增不改**（改了会静默出错，不是不方便）：`registry/ports.tsv`、`registry/schemas.tsv`、`registry/permissions.tsv`。理由见 `AGENTS.md` 的「四张钉死的表」。

## 什么时候写客户文档

**等第一个业务组件能跑通闭环之后**（阶段三出档）。现在写只能写出一份「系统将会支持…」的宣传册，而那种东西没人会回来更新它。

届时它至少要有三节：这套系统能做什么 / 你这套装了哪些模块（`/api/tenant/features` 的人话版）/ 想要标准版没有的功能时怎么办（对应设计书 §9.5 定制深度三级）。

---

## 一个组件有四份文档

写组件时看 [`standards/00-master-guide.md`](standards/00-master-guide.md) 的 **SOP-D**，四份缺一不可：

| # | 文件 | 在哪 | 给谁看 |
|---|---|---|---|
| 1 | `docs/design/<仓库名>.md` | **本仓库** | 做设计决策的人。跨组件对照着看 |
| 2 | `README.md` | 组件仓库根 | 「要不要装它、怎么装」的人 |
| 3 | `docs/手册.md` | 组件仓库 | 「已经装了、要用它 / 要改它」的人 |
| 4 | `AGENTS.md` + `CLAUDE.md` | 组件仓库根 | AI 助手 |
