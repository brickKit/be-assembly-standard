# crm-opportunity · 商机管理 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `crm/opportunity` |
| 仓库名 | `crm-opportunity` |
| 端口 | HTTP `8102` / gRPC `9102` ← 抄 `registry/ports.tsv` |
| schema / role | `crm_opportunity` / `crm_opportunity_rw`（归档 `crm_opportunity_archive`） |
| 语言 | Go |
| 框架栈 | Gin + `database/sql`+`pgx stdlib` + `sqlc` + `golang-migrate`（设计书 §12.4） |
| 合并部署时进 | **外壳二 `go-backoffice`** |
| 装配角色 | `optional` |
| 阶段 | 第三阶段 |

> 本组件是阶段三**唯一的业务组件**，也是附录 E 那条链路的**起点**。
> ⚠️ 规范源里最要紧的一条是设计书 **§1.4**：**CRM 与 ERP 零同步边，仅事件握手**（§6 展开）。

## 1. 边界

**归我：**

- **商机全生命周期**：建档、阶段推进、赢单/输单，以及它的历史。
- **商机行**：这次机会打算卖哪些产品、多少量、什么价（**快照**，见 §2.1）。
- **漏斗与赢单预测所需的原始数据**：阶段、金额、概率、预计成交日。
- **赢单时发出那条事件**——链路的扳机（§4）。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| **订单** | `erp-sales` | 赢单之后的事全归它。**我发完事件就不再关心后续**——订单建没建成、库存够不够、要不要补偿，我一概不知道也不该知道 |
| 客户主数据 | `mdm-customer` | 我持 `customer_id` 与展示快照 |
| 产品与价格 | `mdm-product` / `erp-sales` | 商机行上的单价是**报价快照**，不是权威价目表（§2.1） |
| 跟进记录、拜访、通话 | `crm-activity`（阶段六） | 本阶段不做。⚠️ 别顺手在 `opportunities` 上加 `last_contact_note` 这类字段——那是另一个组件的聚合根 |
| 线索 | `crm-lead`（阶段六） | 线索转商机是那时的事 |

**数据权限**：`data_scopes` **两维**（§14.2.2：CRM 全域都需要行级过滤，"私海"就是这个意思）：

```yaml
data_scopes:
  - { dimension: org,   column: dept_path, mode: prefix, tables: [opportunities] }
  - { dimension: owner, column: owner_id,  mode: equals, tables: [opportunities] }
```

⚠️ **与 `erp-sales` 的两维完全一致**，这是刻意的：赢单转订单时**订单要继承商机的归属**（§4.1），
两边维度对不上就会出现"商机我看得见、转出来的订单我看不见"。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `opportunities` | 不分区 | — | 商机主体。含 `customer_id`、`owner_id`、`dept_path`、`stage_id`、**`expected_amount`**、**`probability`(0–100)**、`expected_close_date`、`status`。⭐ 加权金额 = `expected_amount × probability`，**算出来不存**（派生值存了就会漂移） |
| `opportunity_items` | 不分区 | — | 商机行：产品、数量、报价快照 |
| `opportunity_stage_history` | 不分区 | — | 阶段流转历史，**只增不改**：从哪个阶段到哪个阶段、谁改的、什么时候 |
| `opportunity_stages` | 不分区 | — | 阶段定义（名称、顺序、默认概率、是否终态）。**迁移播种**，见 §2.2 |
| `customer_snapshots` | 不分区 | — | `mdm-customer` 事件的摘要副本（客户名等展示字段） |
| `command_idempotency` / `event_outbox` / `event_inbox` | `created_at`（后两张） | 周 | 标准三张 |

强制字段全部符合 §11.2.1。

**终态列表**（归档扫描靠它，§11.5.2）：`WON` / `LOST` / `CANCELLED`。活跃态：`OPEN`。

⚠️ **不分区**——跟随 §11.2.5 的清单（那张表里有 `crm-activity`，**没有** `crm-opportunity`）。理由站得住：
活动记录是每次通话/拜访一行，商机是每个销售机会一行，**量级差一到两个数量级**。

### 2.1 商机行的单价是"报价快照"，不是权威价格

建商机行时从 `mdm-product` 取产品信息、从本地算或人工填一个报价，**快照进 `opportunity_items`**。

⚠️ **赢单转订单时，`erp-sales` 会用它自己的定价引擎重算价格**（它的 `CalculatePriceDryRun`，设计计划 §3.2），
**不会照抄我的报价**。这是刻意的：定价规则归 `erp-sales`（设计书 §5.5：定价模块在 erp-sales 内部），
我这里的数字是**销售谈判时的记录**，两者可以不一致。

**所以 `crm.opportunity.won.v1` 里带不带单价？带**——但它的语义是"当时谈的是这个价"，供 `erp-sales` 参考
或做差异提醒，**不是命令它按这个价建单**。这一条要写进事件的字段注释里，否则下一个人会以为是权威价。

### 2.2 阶段（stage）是数据不是代码

阶段清单（如：初步接洽 → 需求确认 → 方案报价 → 商务谈判 → 赢单）**存表、迁移播种**，
不写死在代码里——同 `mdm-product` 的 UoM、`erp-inventory` 的仓库、`erp-sales` 的价目表先例。

⚠️ **但"阶段推进的规则"不做成配置**：本阶段任意阶段之间都可以跳转（只记历史），
不实现"必须按顺序推进""跳阶段要审批"这类约束。理由见 §8 的 R-4 判定。

## 3. 契约面

**gRPC（`crm.opportunity.v1.OpportunityService`）：**

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `CreateOpportunity` | 命令 | ✅ | 建档。校验客户与产品（§5） |
| `UpdateOpportunity` | 命令 | ✅ | 改金额/预计成交日/负责人 |
| `ChangeStage` | 命令 | ✅ | 阶段推进，写历史 |
| `MarkWon` | 命令 | ✅ | ⭐ **链路的扳机**：转 `WON` + 写 Outbox（§4.1） |
| `MarkLost` | 命令 | ✅ | 转 `LOST`，要求填原因 |
| `GetOpportunity` / `BatchGetOpportunities` | 读 | — | §3.8 强制的 `batchGet` |
| `ListOpportunities` | 读 | — | 漏斗视图的数据源，**走 `ScopeFilter`** |

**对外 REST 路径前缀：** `/crm/opportunity/**`

| 路径 | 权限键 |
|---|---|
| `GET /opportunities` / `GET /opportunities/{id}` | `crm.opportunity.view` |
| `POST /opportunities` / `PATCH /opportunities/{id}` | `crm.opportunity.edit` |
| `POST /opportunities/{id}/stage` | `crm.opportunity.edit` |
| `POST /opportunities/{id}/win` | **`crm.opportunity.win`** |
| `POST /opportunities/{id}/lose` | `crm.opportunity.edit` |

⚠️ **赢单单独一个权限键**，不与普通编辑合并——它会触发建单、锁库存、生成应收一整条链路，
**是本组件唯一有下游财务影响的动作**。

### 3.1 跨组件调用复用阶段二立下的 vendored-contract 模式

调 `mdm-customer` / `mdm-product` 的 `BatchGet` 时，按 `erp-sales` 在阶段二立的先例做
（`erp-sales` 设计计划 §9、阶段二复盘 §2.3）：

```
contracts/vendor/{mdm/customer,mdm/product}/   两份契约的只读镜像（逐字复制，只改 go_package）
buf.yaml 拆两个 module                          本组件契约 STANDARD lint；vendor 镜像 MINIMAL + 豁免 PACKAGE_DIRECTORY_MATCH
本地 buf generate                               生成自己的客户端 stub
```

⚠️ **不许 import `mdm-*` 仓库的 Go 代码**（铁律六），`make gates` 的 import 扫描会拦。
⚠️ **用 `besdk.UserClient`（透传 JWT），不许用 `SystemClient`** ——这是用户请求路径，
`SystemClient` 会绕过下游数据权限（导读第 21 条，`make gates` 扫）。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| ⭐ `crm.opportunity.won.v1` | **核心交易事件** | `MarkWon` 成功提交后，经 Outbox | 见 §4.1 的完整字段表 |
| `crm.opportunity.lost.v1` | 旁路 | `MarkLost` 后 | `opportunity_id`、`reason`、`amount`。供未来的 BI 分析 |
| `crm.opportunity.stage_changed.v1` | 旁路 | 阶段变更 | `opportunity_id`、`from_stage`、`to_stage`。供漏斗转化率分析 |

⚠️ **subject 名是三段 `crm.opportunity.won.v1`，不是两段 `opportunity.won.v1`。**
设计书 §3.7 的命名法是 `{domain}.{aggregate}.{action}`，而这个名字**曾经写错过、后来统一了**
（设计书 §942 专门记了一笔）。**现在是唯一还能改的窗口——`erp-sales` 的 handler 还没实现**；
一旦它开始消费，改名等于删掉旧 subject（决策 19：只增不删不改）。

**消费：**

| subject | 来自 | 做什么 | 幂等与乱序怎么处理 |
|---|---|---|---|
| `mdm.customer.created.v1` / `.updated.v1` | `mdm-customer` | 维护 `customer_snapshots` 展示字段 | 按 `version` 单调比较，旧的丢弃 |

⚠️ **不消费 `erp-sales` 的任何事件。** 赢单之后订单建成没有、发货没有，**我一概不追踪**——
那会让 CRM 反向依赖 ERP 的状态机（§6）。想在商机上看到"已转订单"，正确做法是**前端/BFF 分别查两边再聚合**
（§4.7 展示上推），不是我去持有订单状态。

### 4.1 ⭐ `crm.opportunity.won.v1` 的字段：`erp-sales` 靠它建单，有一个字段极易漏

**`erp-sales` 的设计计划 §4 已经把这条 subject 占位了**（原文："阶段二 subject 先在事件清单占位，不实现 handler"），
但**没有定过 payload 形状**——所以形状在这里定死。⚠️ **阶段二 `erp-finance` 消费 `sales.order.created.v1`
时字段名猜错（`amount` ≠ `total_amount`，复盘 §2.1），根因就是"两份设计计划各写各的"。这次先对齐再写。**

| 字段 | 必填 | `erp-sales` 拿它干什么 |
|---|---|---|
| `opportunity_id` | ✅ | **幂等来源**：它的四元组是 `(crm-opportunity, opportunity, opportunity_id, revision)` |
| `customer_id` | ✅ | 建单的客户；它会自己再 `BatchGet` 校验一次 |
| `items[]`（`product_id`/`quantity`/`quoted_unit_price`） | ✅ | 订单行。⚠️ `quoted_unit_price` 是**报价快照供参考**，它会用自己的定价引擎重算（§2.1） |
| ⭐ **`owner_id`** | ✅ | **最容易漏的一个**，见下 |
| ⭐ **`dept_path`** | ✅ | 同上 |
| `currency` | ✅ | 本位币（标准版单币种，§5.5），留字段不留逻辑 |
| `expected_close_date` | — | 供它推算交期 |
| `revision` | ✅ | 乱序保护 |

⚠️⚠️ **`owner_id` 与 `dept_path` 为什么必须带：`erp-sales` 的 handler 里没有用户身份。**

普通建单是用户请求，`owner_id`/`dept_path` 从 JWT 来。而**赢单转订单是在事件 handler 里发生的**——
按 §14.2.6，事件 handler 用的是 `SystemClient`/系统身份，**JWT 根本不存在**。这时如果事件里没带归属：

| 漏带的后果 | 症状 |
|---|---|
| `owner_id` 为空 | 订单没有归属人，**"我的订单"列表里谁都看不到它** |
| `dept_path` 为空 | `org` 维前缀匹配匹配不上，**除了超级管理员谁都看不见这张单** |

**而且不报任何错**——订单建出来了、库存也占了、应收也生成了，只是**列表里查不到**。
这是"不报错、无症状"故障的又一个典型。

⚠️ **所以规则是：归属跟着商机走。** 赢单转出来的订单，负责人与部门就是商机的负责人与部门。

## 5. 依赖

**强依赖**（同步 gRPC）：

| 组件 | 调它的什么 | 为什么必须同步 |
|---|---|---|
| `mdm/customer` | `BatchGet` | 建商机时校验客户存在、取展示快照。**建档那一刻就要挡住脏数据**，事后对账挡不住 |
| `mdm/product` | `BatchGet` | 商机行的产品校验与快照 |

**弱依赖**：无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| ⭐ **`erp-sales`** | **§1.4 铁律：CRM 与 ERP 零同步边，仅事件握手。** 这是本组件最重要的一条禁令，见 §6 |
| `erp-inventory` / `erp-finance` | 同上，而且更远——商机阶段根本不该知道库存和应收的存在 |
| `infra-workflow` | 本阶段商机不走审批。⚠️ 将来"大额商机赢单要审批"是**业务规则**，那时也是我调 workflow，不是反过来 |
| `infra-iam-casdoor` | JWT 本地验签，`iamJwksUrl` 配置项 |

## 6. 在同步图与三枢纽里的位置

**我在同步图上有两条出边**（`mdm/customer`、`mdm/product`），**零入边**。

**无环证明**：两个 `mdm` 都是只读枢纽、零出边（各自设计计划 §5），所以从我出发的路径长度恒为 1。

⚠️⚠️ **"CRM 与 ERP 零同步边"这条铁律在本组件身上第一次真正被考验**，因为附录 E 那条链路
**看起来**就是"商机赢单 → 建订单"，很容易顺手写成一次同步调用。为什么不能：

| 如果建了 `crm-opportunity → erp-sales` 同步边 | 后果 |
|---|---|
| 两个域的事务耦合 | 赢单这个动作会因为库存不足/应收失败而失败——**而销售明明已经赢了** |
| CRM 装配上就绑死 ERP | 只买 CRM 不买 ERP 的客户装不了（本组件是 `optional`，ERP 也是） |
| 同步图跨域 | §1.4 的整条边界失效，后续 `crm-*` 七个组件会照抄这个先例 |

**正确形态是事件握手**：我把"赢了"这个**事实**广播出去，谁关心谁消费。**订单建不建得成，与商机赢没赢
是两件独立的事**——这也是 §4 里"不消费 `erp-sales` 任何事件"的同一条道理的另一面。

⚠️ 这一点在阶段三 Task 14 的全链路验证里要**真的验一次**：制造一次库存不足，
断言**商机仍然是 `WON`**、订单没建成、`erp-sales` 的补偿链正常——**CRM 侧的状态不回滚**
（阶段三计划 Task 14 已列进验证清单）。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `opportunities` | `OPEN` 的永远热 | 终态（`WON`/`LOST`/`CANCELLED`）且超过 **24 个月** | `crm_opportunity_archive` |
| `opportunity_items` / `opportunity_stage_history` | 跟随主表 | **跟随主表一起归档**（§11.2.4） | 同上 |
| `opportunity_stages` / `customer_snapshots` | 永久热 | 不归档 | — |

⚠️ **归档窗口 24 个月，比 `erp-sales` 的 12 个月长**：销售分析要看**同比**（今年 Q3 对去年 Q3），
12 个月的窗口刚好把去年同期切掉。⚠️ 判据仍然是"终态 **且** 够老"——一个开了三年还没结的商机不能归档。

## 8. 参考实现

> 完整调研过程见 [`_调研记录/03-阶段三.md`](./_调研记录/03-阶段三.md) 的「crm-opportunity」一节。下表是精炼版。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Odoo | 📋 开工前填 | `crm.lead` 字段构成、`crm.stage`、赢单转报价的动作 | ✅ **已查证**：`probability`(0–100，**可由阶段自动带出、也可手工覆盖**——直接回答了本文件 §9 第 4 条)、`expected_revenue`（赢单预期金额）、加权 = 两者相乘、失单必须记 `loss reason`。**阶段存表不写死**（§2.2）；**它的赢单转订单是手工按钮**不是自动——见下方 R-4。⚠️ 另注意它 `probability=100` 即视为赢单自动关闭，**我们不学**：赢单是显式的 `MarkWon` 动作（它会触发建单，不能被一个百分比数字顺手触发） | LGPL-3 | 借鉴逻辑 |
| ERPNext | 📋 开工前填 | `Opportunity` doctype、`opportunity_from`、转 Quotation 的流程 | 商机行的快照字段构成 | GPL-3 | 借鉴逻辑 |
| SuiteCRM / Salesforce | — | 商机的概率加权预测、漏斗阶段模型 | `probability` 与阶段绑定的默认值（§2.2）；**闭源产品的选配测试素材**：销售天天用的是"改阶段、改金额、看漏斗"，复杂的预测模型很少有人碰 | 闭源 | 借鉴实际应用 |

**明确没有参考的**：营销自动化（campaign/nurturing）那一套。**不是没查，是不在本组件边界内**——
那是 `crm-campaign`（阶段六）的事。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| Odoo | 线索与商机**同一张表**用 `type` 区分 | 两者的生命周期与数据权限画像不同（线索是公海、商机是私海）。我们分成 `crm-lead` 与本组件两个仓库——**这正是"一个组件一个聚合根"的取舍**（§2.6） |
| 多数 CRM | 商机上挂"已转订单/已开票"的状态字段 | 那要么是同步查 ERP（违反 §1.4），要么是消费 ERP 事件反向同步（让 CRM 依赖 ERP 状态机）。**展示上推**（§4.7） |
| 多数 CRM | 阶段推进规则做成可配置流程 | 见下方 R-4 |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

⭐ **有两条，都判定为 Fork 点，不建族。**

| 分歧 | 现实中的分歧 | 判定 |
|---|---|---|
| **赢单转订单：自动还是人工确认** | **Odoo 是手工按钮**（销售赢单后点"新建报价单"）；也有产品做成自动。两种都合理——**自动适合标准化程度高、单价低的业务；人工适合需要二次确认合同条款的大单** | 真实分歧。**本阶段做自动**（附录 E 的链路要求），Fork 点记下 |
| **阶段推进的约束** | 任意跳转（我们）/ 必须顺序推进 / 跳阶段要审批 | 真实分歧，与客户的销售管理成熟度相关 |

**为什么都不能做成 slot**（R-4 第 3 步）：本组件被 `frontend-standard`、`infra-bff-mobile` 读取，
未来还会被 `crm-*` 其它组件依赖；而"赢单转订单"那条分歧**同时长在 `erp-sales` 里**（它是消费方，
决定收到事件后建不建单），而 `erp-sales` 被更多组件依赖。按 §5.11 硬约束 → **落点是 `customer_fork`**。

与阶段二那 9 条、本阶段 `infra-workflow` 的审批路由、`infra-print` 的模板形态**结论完全一致**——
到目前为止，**交易与业务组件上的每一条分歧都落在 Fork，没有一条能做成 slot**（复盘 §4 第 5 条）。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | 赢单时客户还不是正式客户怎么办？（CRM 里常见：先有商机、赢了才建档） | 阶段三实现时 | 📋 本阶段**要求客户必须已在 `mdm-customer` 存在**（`CreateOpportunity` 就校验）。⚠️ "潜在客户"是 `crm-customer`（阶段六）的概念，不在本阶段 |
| 2 | `erp-sales` 消费赢单事件建单失败时（如库存不足），要不要通知回 CRM？ | 阶段三 Task 14 实测后 | 📋 **不通过事件回传**（会让 CRM 依赖 ERP 状态）。正确路径是 `erp-sales` 自己建 `infra-workflow` 异常待办通知销售——**待办的 `assignee` 用事件里带的 `owner_id`**，正好是 §4.1 那个字段的第二个用途 |
| 3 | 漏斗分析要不要在本组件做，还是留给 `ana-bi`（阶段六）？ | 阶段六 | 📋 本阶段只做**最简单的按阶段分组统计**（一个 `ListOpportunities` 的聚合查询）。⚠️ 复杂的转化率/预测留给 `ana-bi`，**不要在业务组件里长出 BI** |
| 4 | ~~`probability` 是跟着阶段自动带出，还是允许手工覆盖？~~ | ~~阶段三定契约时~~ | ✅ **已定（查证 Odoo 后）**：**阶段带默认值 + 允许手工覆盖**，两者都存，加权金额用实际值。这正是 Odoo 的做法，且它把 `probability` 与 `expected_revenue` 分开存、加权值即时算不落库——我们照做 |
