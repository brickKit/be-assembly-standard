# erp-sales · 销售管理 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `erp/sales` |
| 仓库名 | `erp-sales` |
| 端口 | HTTP `8084` / gRPC `9094`（`registry/ports.tsv`） |
| schema / role | `erp_sales` / `erp_sales_rw`（归档 `erp_sales_archive`，**本组件真的会用**，见 §7） |
| 语言 | Go（设计书 §12.1.2：erp 核心交易域） |
| 框架栈 | Gin + `database/sql` + `pgx/v5/stdlib` + `sqlc` + `golang-migrate`（§12.4 锁定表） |
| 合并部署时进 | 外壳一 `go-core` |
| 装配角色 | `default` |
| 阶段 | 阶段二（验平台，设计书 §9.6 档 1）。**设计书 §8.2 的"标准砖样板 B"就是本组件** |

## 1. 边界

**归我：** 销售报价与订单的生命周期、订单行、**定价（价格表/折扣）**、防超卖的**发起方**逻辑、TCC 补偿编排。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| 客户是谁、信用额度**值** | `mdm-customer` | 建单时 `BatchGet` 校验 + 快照到订单行 |
| 产品是什么、单位换算 | `mdm-product` | 同上 |
| 库存够不够、预留 | `erp-inventory` | 本组件**发起** `Reserve`，但判定"够不够"的物理位置在库存那边的一条 SQL 条件里（§2.2 of `erp-inventory`）。**发起方不许自己算够不够** |
| 应收凭证、已用额度**权威值** | `erp-finance` | 本组件发事件，财务生成凭证 |
| 发货的物理执行、物流单 | 阶段六的 `erp-*` / `integration-*` | 本组件的 `ShipOrder` 只是状态流转 + 通知库存出库，不管车怎么派 |
| 审批流程本身 | `infra-workflow`（阶段三，弱依赖） | 决策 27：workflow 严禁含业务规则。本组件发起待办、消费"审批完成"事件，**不把审批逻辑放进 workflow** |

**数据权限判定**（§11.2.1 强制在建表前判定）：**需要，两维**。

```yaml
data_scopes:
  - { dimension: org,   column: dept_path, mode: prefix, tables: [sales_orders] }
  - { dimension: owner, column: owner_id,  mode: equals, tables: [sales_orders] }
```

理由：设计书 §14.2.2 把 `org` 与 `owner` 两维明确列给 `erp-sales`——"我的订单"和"本部门及下级的订单"是销售组织最基本的两个视图。

⚠️ **本组件是全系统第一个真的需要 §11.2.1 那三列的组件**（`dept_id` / `dept_path` / `owner_id`），而且它们要建在**分区表**上——§11.2.1 原话"分区表回头加列的代价比建表时多两个数量级"，这一条在这里第一次真的生效。

⚠️ **`dept_id` / `dept_path` 是创建时快照，不是运行时查"这个人现在在哪个部门"**（§11.2.1 明文）。否则销售换部门后，他去年的订单会在报表里集体漂移——**不报错，数字就是变了**。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `sales_orders` | `created_at` | **月** | §11.2.5 分区大表清单在册 |
| `sales_order_items` | `created_at` | **月** | ⚠️ 子表跟随主表分区（§11.2.4），分区键用**订单头的** `created_at` |
| `pricelists` / `pricelist_items` | 不分区 | — | 价格表，主数据量级 |
| `customer_snapshots` | 不分区 | — | 客户摘要副本：`credit_limit`（来自 mdm）+ `credit_exposure`（来自 finance） |

全部符合 §11.2.1（`created_at`/`updated_at`/`version`/`status`）。

**终态列表：** `COMPLETED`、`CANCELLED`、`CLOSED`（§11.7 的冷数据判据）。

### 2.1 订单状态机

```
DRAFT ──confirm──▶ CONFIRMED ──ship──▶ SHIPPED ──complete──▶ COMPLETED（终态）
  │                    │                                          
  ├──cancel──▶ CANCELLED（终态）◀──cancel──┘                       
  └──────────────────────────────────▶ CLOSED（终态，人工关闭）
```

**三个刻意的决定，每个都与 Odoo 不同：**

| # | 我们的决定 | Odoo 的做法 | 为什么不一样 |
|---|---|---|---|
| 1 | **`CANCELLED` 是终态，不能复活** | `action_draft()` 可以把 cancel 的订单拉回 draft | 我们取消订单时**跨进程释放了库存预留**。复活要重新 `Reserve`，而那时库存可能已经被别人占走——"复活"就会变成"复活一半"。**补偿跨了服务边界就不对称，这是分布式的代价，不是我们保守** |
| 2 | 报价与订单**同一张表 + 状态位** | 同左 | 这一条抄 Odoo，它是对的：报价转订单不该换表，否则单号、行、快照全要搬一遍 |
| 3 | 没有 `locked` 布尔 | Odoo 17 把 16 的 `done` 状态降级成了 `locked` 布尔 | 阶段二不需要"锁定"语义。**记下来**：Odoo 走过"用状态表达锁定 → 改成正交布尔"这条弯路，我们将来真要加时直接加布尔，不要加状态 |

### 2.2 订单行快照：全部快照，不 join

`sales_order_items` 建单时**快照** `product_sku` / `product_name` / `uom` / `unit_price` / `discount` / `tax_rate`，`product_id` 只作为追溯外键。

两个理由，第二个更硬：
1. 产品改名不该重写历史订单（所有 ERP 的共识；查证 Odoo 的 `sale.order.line` 也是 `compute + store + readonly=False`，即算一次然后当普通列存着）。
2. ⚠️ **产品数据在另一个进程另一个 schema 里，物理上 join 不到**（决策 3 的墙）。单体 ERP 里"要不要 join"是个权衡，在我们这里**根本没有 join 这个选项**——不快照就只能每次读订单都发一次 `BatchGet`。

## 3. 契约面

**gRPC（`erp.sales.v1.SalesService`）：**

| rpc | 类型 | 幂等键 | 权限键 | 说明 |
|---|---|---|---|---|
| `CreateOrder` | 写 | `idempotency_key` | `erp.sales.create` | 建单（`DRAFT`）。**不预留库存** |
| `ConfirmOrder` | 写 | `idempotency_key` | `erp.sales.confirm` | ⚠️ **TCC 链在这里**（§3.1） |
| `CancelOrder` | 写 | `idempotency_key` | `erp.sales.cancel` | 释放预留、发事件 |
| `ShipOrder` | 写 | `idempotency_key` | `erp.sales.ship` | 预留转实际出库（调 `ConfirmIssue`） |
| `CalculatePriceDryRun` | 读 | — | `erp.sales.view` | ⚠️ **前端/BFF 严禁自己算钱**（§5.5、§8.4），只能调它 |
| `GetOrder` / `ListOrders` | 读 | — | `erp.sales.view` | 游标分页 + 强制时间窗口 |
| `BatchGetOrder` | 读 | — | `erp.sales.view` | 防 N+1（§3.8） |
| `GetOrderStatus` | 读 | — | `erp.sales.view` | ⚠️ 给**上游**（阶段三的 `crm-opportunity`）防薛定谔超时用（§4.5） |

**对外 REST 路径前缀：** `/erp/sales/**`
**不暴露到 REST：** `BatchGetOrder` / `GetOrderStatus`（组件间协议）。
**`CalculatePriceDryRun` 必须暴露到 REST**——前端下单页要实时试算（§8.4 明确要求走后端 DryRun 接口 + 前端防抖）。

### 3.1 `ConfirmOrder` 的 TCC 链（本阶段最难的一段代码）

```
① BatchGet 客户（mdm-customer）        ─ 失败 → 直接返回，无需补偿
② BatchGet 产品（mdm-product）         ─ 失败 → 直接返回，无需补偿
③ 本地缓存校验信用额度                  ─ 超限 → 直接返回，无需补偿（零网络开销）
④ Reserve 库存（erp-inventory）        ─ 失败 → 直接返回；超时 → 见下
⑤ 建单 + PublishOutbox（同一事务）      ─ 失败 → 补偿：CancelReservation
```

⚠️ **④ 超时的处理是唯一不能"想当然"的一步**（§4.5 薛定谔的超时）：

```
Reserve 超时
  → 调 GetReservationStatus（严禁直接 CancelReservation）
      RESERVED  → 当作成功，继续 ⑤
      NOT_FOUND → 请求根本没到，安全重试或失败返回
      CANCELLED → 已被撤销，失败返回
      查询也超时 → 写本地「待对账」表，交给定时对账兜底（§4.4.3）
```

⚠️ **补偿连续失败 3 次 → 订单标 `SUSPENDED` + 告警**（§4.4.4）。阶段三接 `infra-workflow` 建一条 `type: exception` 待办；**阶段二只标状态 + 打日志，绝不无限重试**——"补偿的补偿"死循环比不补偿更糟。

**§4.4.4 落地细节**（阶段三 Task 8，`infra-workflow` 建成后补齐——阶段二写下这条时它还不存在，只留了占位）：

```
attempts >= 3 → SuspendOrderTx（DRAFT → SUSPENDED）
             → CreateTask(type: EXCEPTION, assignee_sub: exceptionAssigneeSub,
                           source: erp/sales/sales_order/<order_id>,
                           deep_link: /erp/sales/orders/<order_id>)
人在 infra-workflow 的"我的待办"里调查后点"同意"（= 确认已人工处理完毕）
             → infra.workflow.task.completed.v1（action: APPROVED）
             → 本组件消费者 ResumeFromExceptionTx（SUSPENDED → DRAFT，
                compensation_attempts 清零）
             → 订单回到可以被重新 ConfirmOrder 的起点
```

⚠️ 三个关键判据：

1. **恢复目标是 `DRAFT`，不是"当作已确认"**——`FinalizeConfirm` 从未提交成功过（正是它失败才触发补偿），订单本来就没有一个可恢复的"已确认"状态；`DRAFT` 是 `ConfirmOrder` 本身要求的起点，恢复到这里就能被重新调用，不需要发明新状态。是否自动重试不在本组件职责内——阶段二的铁律"绝不无限重试"同样适用于这里，重新确认由人或调用方显式发起。
2. **本组件从不调 `infra-workflow` 的 `CloseTask`**——那是组件间协议（人代表业务组件创建/关闭待办等于绕过业务规则，见 `infra-workflow` 的 REST 契约警告）。exception 任务由**人**通过 `infra-workflow` 通用的"我的待办"UI 点"同意"来关闭，本组件只是这条事件的**消费者**，不是发起方。因此本组件永远不会收到 `action: RESOLVED`，只处理 `APPROVED`；收到 `REJECTED` 时不做任何自动动作（语义不明确，交给人后续另行处理，不猜测）。
3. **`ResumeFromExceptionTx` 用 `suspended_reason` 精确匹配，不是只判 `status == SUSPENDED`**——避免一张后来又被权威额度判定（`finance.credit.rejected.v1`）覆盖过 `suspended_reason` 的订单被这条事件误恢复：两条 `SUSPENDED` 来源共用同一个 `status` 值但语义不同，只有 `reason` 能区分。

**幂等键**：`CreateTask` 用 `ConfirmOrder` 命令自己的 `idempotency_key + ":exception-task"` 派生——同一个确认命令的重放（网络重试）应该拿到同一条待办；订单从 `SUSPENDED` 恢复后如果再次补偿失败 3 次，调用方必须带一个全新的 `idempotency_key` 发起新的 `ConfirmOrder`，天然产生一条新的待办，不会撞上旧的 `command_idempotency` 记录（`infra-workflow` 的 `command_idempotency` 永不过期，这条设计前提必须成立，否则第二次挂起会静默复用第一次的旧任务）。

**审批人**：本阶段没有 `mdm-org`（阶段五才建），`assignee_sub` 来自新增配置项 `exceptionAssigneeSub`（留空 = 跳过建待办，只打日志，同 `infra/workflow` 弱依赖缺失的判据——两个独立的"跳过"开关）；`assignee_dept_path` 留空（站在部门树根节点的人天然看得到全部，阶段五 `mdm-org` 上线后再补真实部门路径）。

⚠️ **③ 与 §8.2 的顺序不同，是刻意的。** 设计书 §8.2 写的是"校验客户与产品 → 预留库存 → 校验信用额度"。我们把零成本的本地信用校验**提到网络调用之前**：按原顺序，一张明显超额度的单会先占住库存再被拒、再补偿释放，白白产生一次预留 + 一次补偿。**这属于实现顺序而非边界变更，出档时回填设计书 §8.2**（见 §9 第 1 条）。

⚠️ **四条边全部用 `besdk.UserClient`（透传 JWT），不许用 `SystemClient`。** 这是用户请求路径，用 `SystemClient` 会绕过下游的数据权限——导读第 21 条，**不报错，返回的数据只是"多了一些"**。`make gates` 有扫描守着（阶段二 Task 2）。

### 3.2 定价：取 Odoo 的模型 + metasfresh 的一个字段

查证两家的做法差异很大（§8）。**结论：主体用 Odoo 的有序表模型，但补上 metasfresh 的 `price_limit`。**

| 取谁的 | 什么 | 为什么 |
|---|---|---|
| **Odoo** | 价格表 = 一张**有序规则表**，按 `(适用范围特异度, 最小数量 desc, 分类 desc, id desc)` 排序**第一条命中的赢** | 简单、可预测、一条 SQL 出结果。metasfresh 的规则链更强但要引入"规则引擎"，而总纲 SOP-R 明确警告 metasfresh 的规则引擎"过度可配置，交付现场没人会配" |
| **metasfresh** | `price_limit`（最低售价）作为**一等字段**，不是公式里的一个参数 | Odoo 把价格下限做成公式参数（`price_min_margin`），要审计"这单为什么能低于底价"时算不清。一等字段几乎零成本，且它是**销售最常被审计的一条** |

价格表规则的适用维度：`全局 / 产品分类 / 产品`（三档，对应 Odoo 的 `applied_on`）+ `min_quantity` + 生效日期区间。

⚠️ **一条规则出全部结果**（单价 + 折扣 + 底价），不做规则叠加。Odoo 的"第一条赢"能回答"为什么是这个价"，叠加式则要重放整条链——而**交付现场最常被问的就是这个问题**。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `sales.order.created.v1` | 核心交易事件 | `ConfirmOrder` 成功提交后（**不是 `CreateOrder`**），经 Outbox | `order_id`/`order_no`/`customer_id`/`items[]`/`total_amount`/`version` |
| `sales.order.cancelled.v1` | 核心交易事件 | `CancelOrder` 成功后 | `order_id`/`reason` |
| `sales.order.shipped.v1` | 核心交易事件 | `ShipOrder` 成功后 | `order_id`/`items[]` |

⚠️ **发在 `ConfirmOrder` 不是 `CreateOrder`**：草稿单不该产生应收凭证。这一条与状态机（§2.1）绑死。

**消费：**

| subject | 来自 | 干什么 |
|---|---|---|
| `finance.credit.rejected.v1` | `erp-finance` | 权威额度判定超限 → 订单转 `SUSPENDED` 并告警（§5 三方分工的第二次判定） |
| `mdm.customer.created.v1` / `.updated.v1` | `mdm-customer` | 维护 `customer_snapshots.credit_limit` |
| `infra.workflow.task.completed.v1` | `infra-workflow`（**阶段三**，弱依赖） | 补偿异常待办被人工确认（`action: APPROVED`）→ 订单从 `SUSPENDED` 恢复回 `DRAFT`（§3.1、§4.4.4）。只处理 `source_component=="erp/sales" && source_aggregate=="sales_order"` 且 `action=="APPROVED"` 的记录，其余原样忽略——同一个 subject 是全平台共用的，不能假设每一条都是自己的 |
| `crm.opportunity.won.v1` | `crm-opportunity`（**阶段三**） | 赢单自动转订单（附录 E）。阶段二 subject 先在事件清单占位，不实现 handler |

⚠️ **本行是 Task 16 实现前修正的一处契约缺口**：本设计计划原文这里还写着"消费 `finance.voucher.posted.v1` 维护 `customer_snapshots.credit_exposure`"——写契约时对照 `erp-finance` 已经真实存在的事件清单（`erp-finance` Task 12，`contracts/events/finance.events.json`）才发现 `finance.voucher.posted.v1` 的 payload 只有 `entry_id`/`entry_no`/`post_no`/`period`/`amount`，**没有 `customer_id`**——它是"旁路分析事件"（grade: peripheral），设计成一般性的"有凭证过账了"广播，不是 AR 专用的客户额度变更信号，字段形状回答不了"是哪个客户"。**改法：不消费它**。`customer_snapshots.credit_exposure` 的新鲜度完全交给 §9 第 4 条已经写好的定时对账（`BatchGetCreditExposure`）来做——那条本来就是为处理漂移设计的兜底机制，恰好覆盖了这里，不需要再叠加一条事件消费。给 `finance.voucher.posted.v1` 加 `customer_id` 字段技术上可行（纯追加，向后兼容），但会把一个通用广播事件的语义拉向 AR 专用，本阶段判定不值得为此改一个已经打了 v1.0.0 标签的组件。

## 5. 依赖

**强依赖（四条，全在本组件身上）：**

| 依赖 | 用它做什么 | 调用点 |
|---|---|---|
| `mdm/customer` | `BatchGet` 校验客户 + 取快照 | `ConfirmOrder` ① |
| `mdm/product` | `BatchGet` 校验产品 + 取快照 + `ConvertQuantity` | `ConfirmOrder` ②、`CalculatePriceDryRun` |
| `erp/inventory` | `Reserve` / `CancelReservation` / `GetReservationStatus` / `ConfirmIssue` | `ConfirmOrder` ④、`CancelOrder`、`ShipOrder` |
| `erp/finance` | `CheckPeriodOpen`（改历史单前）、`BatchGetCreditExposure`（对账时校准快照） | 改历史单、定时对账 |

**弱依赖（`optional: true`）：**

| 依赖 | 用它做什么 | 缺失时怎么办 |
|---|---|---|
| `infra/workflow` | 补偿失败的 `type: exception` 待办 + 消费其完成事件恢复订单（§3.1、§4.4.4，阶段三 Task 8 已接通） | 缺失时**不注入 `INFRA_WORKFLOW_ENDPOINT` 这个变量**——不是空串，是键根本不存在（§3.6）。本组件必须用 `besdk.Endpoint()` 的**二值返回**判断，`ok == false` 就跳过建待办、只打日志 |

⚠️ **这条弱依赖同时是平台验收用例 5 的天然测试场景**——阶段一验不了它（没有任何弱依赖），本阶段第一次具备验证前提。**所以它不是"顺便写上的"，是本阶段出档条件的一部分。**

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| `crm-*` | ⚠️ **§1.4 铁律：CRM 与 ERP 零同步边，仅事件握手。** 阶段三的赢单转订单走 `crm.opportunity.won.v1` 事件，**绝不能顺手加一条同步调用** |
| `infra-iam-casdoor` | JWT 本地验签（决策 87） |

## 6. 在同步图与三枢纽里的位置

本组件是**唯一的"链上一环"**——§4.2 同步图里它有**四条出边**（指向两个 mdm + inventory + finance），零入边（阶段二内）。三个枢纽都是叶子，本组件是根。

**无环证明：** 四个被依赖方全部零出边（见各自设计计划 §5），所以从本组件出发的任何路径长度都是 1，不可能回到自己。

**不违反 CRM↔ERP 零同步边**：本组件不指向任何 `crm-*`，阶段三的 `crm-opportunity → erp-sales` 是**事件边不是同步边**。

⚠️ **本组件是阶段二"验平台"的主力**：平台的依赖解析、地址注入（`*_ENDPOINT` 变量名由 ID 推导、额外端口以 `http://` 开头）、启停级联、弱依赖缺失——20 条断言里最难的四条（3/4/5/8）全靠它才能验。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `sales_orders` / `sales_order_items` | 草稿、已确认、部分发货（§11.7） | 终态（`COMPLETED`/`CANCELLED`/`CLOSED`）且超过 **12 个月** | `erp_sales_archive` |
| `pricelists` / `pricelist_items` | 永久热 | 不归档 | —— |
| `customer_snapshots` | 永久热 | 不归档 | —— |

⚠️ **归档要判终态，不能只判时间**（§11.5.2）：一张 14 个月前建的、至今还没发货的订单**不能归档**——它还是活的。判据是"终态 **且** 够老"，两个条件都要。

⚠️ 子表跟随主表（§11.2.4）：`sales_order_items` 用**订单头的** `created_at` 做分区键，不用行自己的创建时间。否则补加的订单行会落进不同分区，主表归档时子表搬不干净。

## 8. 参考实现

> 完整调研过程（含函数级细节、来源链接、意外发现清单）见 [`_调研记录/02-阶段二.md`](./_调研记录/02-阶段二.md#erp-sales销售订单与定价)。下表是精炼版。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Odoo | 17.0 | `addons/sale/models/sale_order.py` | 状态机划分（报价与订单同表 + 状态位）；确认动作的原子性边界 | LGPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/sale/models/sale_order_line.py` | **订单行全量快照**（`compute + store + readonly=False`），且 `qty_invoiced > 0` 后拒绝重算价格 | LGPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/product/models/product_pricelist_item.py` | 价格表**有序规则表 + 第一条命中赢**（`_order` 决定优先级）；适用范围三档 | LGPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/sale_stock/models/sale_order.py` | 确认时的库存动作在**同一事务**内同步完成 | LGPL-3 | 借鉴逻辑 |
| metasfresh | master | `de.metas.business/.../pricing/rules/` | `priceStd` / `priceList` / **`priceLimit`** 三值分离——我们取了 `price_limit` 一个字段（§3.2） | GPL-2/3 | 借鉴逻辑 |
| Odoo（闭源使用观察） | —— | `partner_credit_warning` 的实际行为 | 信用额度在成熟系统里**从不硬拦**，只提示；硬拦一律是第三方插件 | LGPL-3 | 借鉴实际应用 |

**明确没有参考的：** 跨服务的 TCC 补偿编排（②–⑤ 那条链）。两个参考系统都是单体单事务，**它们没有这个问题，也就没有这个解**——`erp-inventory` 的设计计划 §8 有同样的结论。这条链的正确性只能靠我们自己的故障注入测试保证（§9 第 2 条）。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| Odoo | 确认订单时**库存不足不报错**，预留能预留的部分，订单照样确认 | 我们**预留失败就整单失败**。理由：我们的 `Reserve` 是跨进程 TCC 的一步，"部分成功"会让补偿语义变成"补偿一部分"，复杂度上一个数量级。⚠️ **这意味着我们比两个成熟系统都严——这是刻意的选择，不是默认值** |
| Odoo | 定价逻辑散落在多个 `_compute` 里（总纲 SOP-R 已点名） | 集中在一个定价模块（决策 69） |
| Odoo 17 | 用 `locked` 布尔取代了 16 的 `done` 状态 | 我们不加锁定语义（§2.1 决定 3）。但记下这条弯路 |
| metasfresh | 规则链 + 折扣方案挂在业务伙伴上，可组合但可配置过头 | 取一个字段不取整套（§3.2）。总纲 SOP-R 的原话："规则引擎过度可配置，交付现场没人会配" |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

⭐ **有，而且这是四份设计计划里发现最多的一处——四条，且其中三条 Odoo 自己就做成了配置项**（这是"该建族"的强佐证）：

| 分歧 | 现实中的两种做法 | Odoo 的配置项 | 判定 |
|---|---|---|---|
| **预留严格度** | 确认即全额预留 / 手工预留 / 按日期预留 | `reservation_method` = `at_confirm`/`manual`/`by_date` | ⭐ 族候选。我们选"确认即全额，不足则整单失败" |
| **缺货策略** | 整单失败 / 部分发货 + 欠单 / 等齐再发 | `create_backorder` = `ask`/`always`/`never`，`picking_policy` = `direct`/`one` | ⭐ 族候选。我们选"整单失败"（最严） |
| **开票基准** | 按订单量开 / 按发货量开 | `invoice_policy` = `order`/`delivery` | ⭐ 族候选。阶段二不做开票 |
| **定价引擎形态** | 有序表第一条赢（Odoo） / 规则链可组合（metasfresh） | —— | ⭐ 族候选。我们选有序表（§3.2） |

⚠️ 按 R-4 第 3 步，建族的硬约束是"**没有任何组件对它建依赖边**"（§5.11）。这四条全都长在 `erp-sales` 内部，而**本组件将来必然被 `crm-*` 与 BFF 依赖**——所以**四条都不能做成 slot**。正确形态是：
- **`customer_fork`**（复制 `erp-sales` 为 `erp-sales-acme` 改这几处）——这正是设计书 §9.5"代码级定制"的标准场景；
- 或分歧小到只是几个分支时用 SOP-P 的内部策略。

**这个判断本身就是本阶段最有价值的产出之一**：它说明"可替换"在 ERP 里的落点，**在交易组件上是 Fork，不是 slot**——slot 适合的是 `frontend-*`、`slot:iam`、`slot:payroll` 这类**没有人对它建依赖边**的位置。写进出档复盘。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | §8.2 的 TCC 步骤顺序把"校验信用额度"排在"预留库存"之后，本设计计划把它提前了（§3.1） | 阶段二出档复盘 | **实现按本计划走**（先本地免费校验再发网络调用），**出档时回填设计书 §8.2**。这属于实现顺序优化，不改边界与契约 |
| 2 | TCC 补偿链没有参考实现，正确性怎么保证？ | 阶段二 Task 17 实现时 | **靠故障注入测试，不是 mock**：让 `erp-inventory` 真的返回库存不足、真的超时（`context.WithTimeout` 掐短），断言订单确实没落库、库存确实没被占住、补偿确实执行了。**用 mock 测这条链等于没测**——要验的正是跨进程的部分 |
| 3 | 订单号 `order_no` 允许有缺口吗？（草稿单删了会留洞） | 阶段二契约定稿时 | **允许有缺口**。查证 Odoo 也是建单时就取号，报价单不转订单就白白消耗一个号。销售单号有缺口不是审计问题——**有缺口不许出现的是会计的 `post_no`**（见 `erp-finance` 设计计划 §2.1），两者不要混 |
| 4 | `customer_snapshots` 与权威值漂移了怎么办？ | 阶段二实现定时对账时 | 与库存余额、财务已用额度同理：**以权威源为准**，快照是缓存。定时对账（§4.4.3）调 `BatchGetCreditExposure` + `mdm-customer` 的 `BatchGet` 比对并修正 |
| 5 | 阶段二要不要做发票（开票）？ | —— | **不做。** 本阶段目标是验平台，`ShipOrder` 之后直接 `COMPLETED`。开票涉及 `invoice_policy` 这个族候选（§8），且会把 `erp-finance` 的契约面撑大一倍——留到阶段五补齐 default 时做 |
| 6 | §4 原文写"消费 `finance.voucher.posted.v1` 维护 `customer_snapshots.credit_exposure`"，但该事件的真实 payload（`erp-finance` 已经建好的契约）没有 `customer_id` | Task 16 写契约时发现 | **改成不消费它**，`customer_exposure` 的新鲜度完全交给已经写好的定时对账（本表第 4 条）。理由见 §4 的行内说明：给事件加字段技术上可行，但会把一个通用广播事件的语义拉向 AR 专用，不值得为此改一个已经打了 v1.0.0 标签的组件 |
| 7 | 契约（Task 16）没有留 `CreatePricelist`/`CreatePricelistItem` 类接口，`CalculatePriceDryRun` 用什么数据算价？ | Task 17 实现时 | 同 `mdm-product` 的 UOM、`erp-inventory` 的仓库先例：**迁移播种**。种一条全局兜底规则（`applied_on='GLOBAL'`，任意产品任意数量都命中），价格是占位值不是真实报价——目的只是让"消费事件→算价→建单→确认→发货"这条链路能跑通，不追求价格的业务正确性。真正的按产品/分类定价留给客户在 `pricelist_items` 里自己录，阶段二没有管理界面/接口 |
| 8 | §4.5 "查询也超时" 分支（`GetReservationStatus` 本身超时）写"交给定时对账兜底"，但兜底要读哪张表？ | Task 17 实现时 | 补一张 `sales_order_reconciliation_queue`（`order_id`/`reservation_id`/`reason`/`created_at`），`ConfirmOrder` 在这个分支直接写一行然后返回，不阻塞用户请求。定时对账任务（本表第 4 条那一个）扩展到同时处理这张队列表——本阶段只把行写进去、做成一张可查的表，真正的对账轮询逻辑同其余"定时对账"一样留到阶段三 |
| 9 | `erp-inventory` 的 `ReserveItem` 要求 `warehouse_id`（设计计划全文、契约都没提过仓库怎么选），本组件的订单行/客户/产品里都没有任何字段能推出该用哪个仓库 | Task 17 实现 TCC 编排时发现 | `erp-inventory` 契约目前**没有**按 code 查仓库 id 的 rpc（只有 `Reserve`/`GetBalance` 等要求已知 id 的接口），多仓选货是完整的 ATP/库存分配算法，远超阶段二"验平台"的目标。**本阶段用一个组件级配置项兜底**：`component.yaml` 加 `configSchema.defaultWarehouseId`（必填，无默认值——留空判空当"配置缺失"直接拒绝启动的错误比默默用错仓库更安全），`ConfirmOrder` 的所有订单行统一用这一个仓库发起 `Reserve`。真正的"按客户/按行选仓库"是阶段三多仓能力的范围，需要 `erp-inventory` 先加一个仓库查询 rpc |
