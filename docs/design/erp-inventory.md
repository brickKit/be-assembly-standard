# erp-inventory · 库存管理 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `erp/inventory` |
| 仓库名 | `erp-inventory` |
| 端口 | HTTP `8086` / gRPC `9096`（`registry/ports.tsv`） |
| schema / role | `erp_inventory` / `erp_inventory_rw`（归档 `erp_inventory_archive`，**本组件真的会用**，见 §7） |
| 语言 | Go（设计书 §12.1.2：erp 核心交易域，强一致 + 高并发写） |
| 框架栈 | Gin + `database/sql` + `pgx/v5/stdlib` + `sqlc` + `golang-migrate`（§12.4 锁定表） |
| 合并部署时进 | 外壳一 `go-core` |
| 装配角色 | `default` |
| 阶段 | 阶段二（验平台，设计书 §9.6 档 1） |

## 1. 边界

**归我：** 库存余额、库存流水、库位/仓库、**库存预留**、防超卖判定。设计书 §2.6 称本组件为**物理命令枢纽**——"这批货现在还有没有、能不能占"这个问题的唯一真相源。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| 产品是什么（SKU、名称、单位、要不要按批次管） | `mdm-product` | 本组件只回答"有多少"，不回答"是什么"。`tracking_type` 我持一份**摘要副本**（§5），不持有它 |
| 为什么要出这批货（订单、生产工单） | `erp-sales` / `erp-manufacturing` | 本组件收到的是"占 3 件"这个命令，**不关心它背后是哪张单**。`order_id` 只作为幂等键与追溯字段存着，不参与任何判断逻辑 |
| 存货的**会计价值**、成本核算分录 | `erp-finance` | 本组件记数量流水（§4 会发 `erp.inventory.adjusted.v1`），财务消费它生成凭证。**数量与金额分家**是本项目与 ERPNext 的关键差异（§8） |
| 采购到货计划、供应商 | `erp-purchase`（阶段六） | 本组件只提供 `Receive`，不关心货从哪来 |

**数据权限判定**（§11.2.1 强制在建表前判定）：**需要**，维度是 `warehouse`。

```yaml
data_scopes:
  - { dimension: warehouse, column: warehouse_id, mode: in,
      tables: [inventory_balances, inventory_movements, inventory_reservations] }
```

理由：设计书 §14.2.2 明确把 `warehouse` 维列给 `erp-inventory`——分仓管理的客户里，华东仓的管理员不该看到华南仓的库存明细。

⚠️ **但本组件不需要 §11.2.1 那三列**（`dept_id`/`dept_path`/`owner_id`）。`warehouse_id` **本来就是业务主键的一部分**，不是为权限额外加的列。三列是给 `org`/`owner` 两维用的，本组件一维都不占——这是"条件强制"里"条件"二字的实际含义。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `warehouses` | 不分区 | — | 仓库/库位主数据，几十行 |
| `inventory_balances` | **不分区** | — | 当前余额。⚠️ §11.2.5 明确注明：**它必须永远小而快**，是防超卖的热点表 |
| `inventory_movements` | `created_at` | **月** | 库存流水，§11.2.5 分区大表清单在册 |
| `inventory_reservations` | 不分区 | — | 未决预留。终态（`CONFIRMED`/`CANCELLED`）的行定期清理，热数据永远小 |
| `product_tracking_snapshots` | 不分区 | — | `mdm-product` 的摘要副本，只有 `product_id` + `tracking_type` + `version`（§5） |

全部符合 §11.2.1（`created_at`/`updated_at`/`version`/`status`）。

**终态列表：**
- `inventory_movements`：**每一行一写入就是终态**（见 §2.1）。
- `inventory_reservations`：`CONFIRMED` 与 `CANCELLED` 是终态；`RESERVED` 不是。

### 2.1 核心设计：流水只增不改，余额是同事务维护的投影

```
inventory_movements   append-only，只 INSERT，永不 UPDATE / DELETE
inventory_balances    与流水在同一个事务里更新；它是投影，也是防超卖的判定点
```

⚠️ **这里与 ERPNext 有一个关键差异，是查证之后刻意选的**（§8）：ERPNext 的 Stock Ledger Entry 号称不可变，**但它的 `qty_after_transaction` 会被 repost 机制 UPDATE 改写**——补录一张过去日期的单据，会触发把该 item-warehouse 之后的所有流水行重算一遍，且这个重算会顺着多物料凭证无界扩散。他们为此付出的代价是：两把 advisory lock、检查点文件、每 2000 行提交一次、去重与跳过逻辑、失败通知，以及一个专门用来发现漂移的"库存差异报表"。

**我们的选择：真的只增不改，代价是阶段二不支持补录过去日期的出入库。** 判据是四把尺子里的"占用知道测试"——补录属于"事后修账"，它的正解是**再记一笔冲销流水**（Odoo 的 `_run_fifo_vacuum` 就是这么做的），而不是回去改历史。

**余额与流水对不上时以流水为准。** 因此必须有一个对账任务（§4.4.3 定时对账兜底）：周期性 `SUM(qty) GROUP BY product_id, warehouse_id` 与余额表比对，不一致就告警并以流水重算。

### 2.2 防超卖：条件更新，不是"先查再写"

```sql
UPDATE inventory_balances
   SET reserved_qty = reserved_qty + $1,
       version      = version + 1,
       updated_at   = now()
 WHERE product_id = $2 AND warehouse_id = $3
   AND on_hand_qty - reserved_qty >= $1;   -- ← 防超卖在这一行
```

`RowsAffected() == 0` 就是库存不足，返回 `FailedPrecondition`。

⚠️ **绝不许写成"先 SELECT 查够不够，再 UPDATE 扣"**——无论两句挨得多近，中间都有窗口，而症状是**偶发超卖**：单元测试永远绿，压测偶尔红，生产上一天错几单，对账时才发现。设计书 §4.4 的原话是"利用数据库行级锁与条件更新实现物理级防超卖"，**条件写在 SQL 的 `WHERE` 里就是"物理级"的含义**。

⚠️ **`(product_id, warehouse_id)` 上必须有唯一约束。** 查证发现 Odoo 的 `stock.quant` **没有**这个约束，因此并发下会产生重复行，靠一个"打开库存界面时触发"的合并任务事后清理，而那个合并还有已知 bug 合不掉并发恰好产生的那种行。我们不接受这个形态——唯一约束 + 条件更新，一次做对。

## 3. 契约面

**gRPC（`erp.inventory.v1.InventoryService`）：**

| rpc | 类型 | 幂等键 | 权限键 | 说明 |
|---|---|---|---|---|
| `Reserve` | 写 | `idempotency_key` | `erp.inventory.reserve` | 预留库存。**跨组件写接口，`erp-sales` 的 TCC 第一步** |
| `CancelReservation` | 写 | `idempotency_key` | `erp.inventory.reserve` | 释放预留。**TCC 的补偿动作** |
| `ConfirmIssue` | 写 | `idempotency_key` | `erp.inventory.issue` | 预留转实际出库：`on_hand` 减、`reserved` 减、写流水 |
| `GetReservationStatus` | 读 | — | `erp.inventory.view` | ⚠️ **防"薛定谔的超时"的唯一手段，不是可选项**（§4.5） |
| `Receive` | 写 | `idempotency_key` | `erp.inventory.receive` | 入库：`on_hand` 加、写流水 |
| `Adjust` | 写 | `idempotency_key` | `erp.inventory.adjust` | 盘盈盘亏调整，写流水 |
| `GetBalance` | 读 | — | `erp.inventory.view` | 单个 `(product, warehouse)` 的余额 |
| `BatchGetBalance` | 读 | — | `erp.inventory.view` | **防 N+1 的唯一合法方式**（§3.8）。下单页面一次查一整单的可用量 |
| `ListMovements` | 读 | — | `erp.inventory.view` | 流水查询，游标分页 + 强制时间窗口（§11.4.1、决策 53） |

**对外 REST 路径前缀：** `/erp/inventory/**`
**不暴露到 REST：** `Reserve` / `CancelReservation` / `ConfirmIssue` / `GetReservationStatus`——**这四个是组件间 TCC 协议的一部分，不是人类操作**。人类操作是"出库单"，那在 `erp-sales` / `erp-purchase` 侧。

⚠️ **`GetReservationStatus` 的四个返回值必须能区分 `NOT_FOUND` 与 `CANCELLED`**：上游超时后查到 `NOT_FOUND` 意味着"我的请求根本没到"（可以安全重试），查到 `CANCELLED` 意味着"到了且已被撤销"（不能重试）。**把两者合并成一个"没有"是错的**，那正是 §4.5 说的"误杀或漏杀"。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `erp.inventory.adjusted.v1` | 核心交易事件 | `Receive` / `ConfirmIssue` / `Adjust` 成功提交后，经 Outbox 发布 | `product_id`/`warehouse_id`/`qty_delta`/`movement_id`/`batch_no`/`serial_no`/`reason` |
| `erp.inventory.transferred.v1` | 核心交易事件 | 调拨（阶段二**不实现**，subject 先在事件清单里占位） | —— |

⚠️ **`erp.inventory.adjusted.v1` 的消费者是 `erp-finance`**（§4.3 事件图）——它据此生成存货科目的凭证。所以 payload 里必须有足够信息让财务算出金额，而**本组件不算金额**：带上 `qty_delta` 与 `product_id`，单价由财务用它自己的成本方法去解。

**消费：**

| subject | 来自 | 干什么 |
|---|---|---|
| `mdm.product.created.v1` / `.updated.v1` | `mdm-product` | 维护 `product_tracking_snapshots` 摘要副本（只取 `tracking_type`）。按 `version` 单调更新（§3.10） |

## 5. 依赖

**强依赖：** 无。
**弱依赖：** 无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| **`mdm-product`** | ⚠️ **本阶段最容易犯的错就是给这里加一条边。** 设计书 §4.2 的同步图里没有 `erp-inventory → mdm-product`。`product_id` 对本组件是**不透明外键**：校验产品存不存在是调用方（`erp-sales`）的事，它在调 `Reserve` 之前已经 `BatchGet` 校验过了，本组件再校验一遍是重复的网络往返 |
| ↑ 那 `tracking_type` 怎么办 | 走**事件摘要副本**（§4 消费段），不走同步调用。代价是有最终一致性窗口——新建的产品可能几百毫秒内 `tracking_type` 还没同步过来。**判据：这个窗口的后果是"新产品第一次入库可能没要求填批次号"，可以靠人工补录修正；而加一条同步边的后果是枢纽变成链上一环，不可逆** |
| `erp-sales` / `erp-finance` | 本组件是被调用方与事件发布方，**没有任何出边**（§2.6） |

## 6. 在同步图与三枢纽里的位置

本组件是三枢纽之一——**物理命令枢纽**。§4.2 里指向它的有 `erp-sales`、`erp-purchase`、`erp-manufacturing`，**它不指向任何人**。在 DAG 里是叶子节点，不可能引入环。

与另两个枢纽的关系：不调 `mdm-*`（见 §5），不调 `erp-finance`（金额是财务自己算的）；`erp-finance` 通过**事件**收到本组件的数量变动，不是同步调用——**这条边在事件图里，不在同步图里**，两张图不能混着看。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `inventory_balances` | **永久热** | 不归档 | —— |
| `inventory_movements` | 最近 12 个月 | 超过 12 个月的整月分区 | `erp_inventory_archive` |
| `inventory_reservations` | `RESERVED` 状态的 | 终态且超过 30 天 | 直接删（它是过程数据，流水里有痕迹） |
| `warehouses` / `product_tracking_snapshots` | 永久热 | 不归档 | —— |

⚠️ **本组件是本阶段第一个真的会用到归档 schema 的组件**——`mdm-customer` / `mdm-product` 的 `*_archive` 都是建了不用。所以 `besdk.BatchGetRouted` 的冷热路由（§11.6.1）在这里第一次真的走归档分支。

⚠️ **余额表永不归档也永不分区。** 它的行数上限是 `SKU 数 × 仓库数`，是个有界值；一旦给它分区或归档，防超卖的那条条件更新就要跨分区找行，热点表立刻变慢——而它是全系统写并发最高的表。

## 8. 参考实现

> 完整调研过程（含函数级细节、来源链接、意外发现清单）见 [`_调研记录/02-阶段二.md`](./_调研记录/02-阶段二.md#erp-inventory库存流水与预留)。下表是精炼版。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| ERPNext | v15 | `erpnext/stock/stock_ledger.py`、`doctype/stock_ledger_entry/` | "流水 + 余额缓存（`Bin`）"的两层结构；**以及它 repost 机制的代价**——这是我们决定不支持补录的直接依据 | GPL-3 | 借鉴逻辑 |
| ERPNext | v15 | `doctype/repost_item_valuation/` | 反面教材：两把 advisory lock + 检查点文件 + 无界级联，都是"允许改写历史"换来的 | GPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/stock/models/stock_quant.py` | `available = quantity - reserved` 这个模型；**以及它并发处理的反面教训**（见下表） | LGPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/stock/models/stock_move.py` | 状态机的状态划分（`draft`/`waiting`/`confirmed`/`partially_available`/`assigned`/`done`/`cancel`），确认只有 `done` 与 `cancel` 是终态 | LGPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/stock_account/models/stock_valuation_layer.py` | **数量与金额分层**：数量在 quant/move，价值在单独的 valuation layer。我们把这条边界画得更狠——金额整个不在本组件 | LGPL-3 | 借鉴逻辑 |

**明确没有参考的（重要）：**

⚠️ **TCC 式的 `Reserve` / `CancelReservation` / `GetReservationStatus` 三件套，在两个参考系统里都没有对应物。**
- ERPNext 的 `Stock Reservation Entry` 没有 TTL、没有幂等键、没有定时释放，只能靠取消或履约来释放。
- Odoo 的 "reservation methods"（`at_confirm` / `manual` / `by_date`）管的是**什么时候开始预留**，从来不管什么时候失效。

**所以这三个接口是我们自己设计的，不是借来的。** 写下来是因为 SOP-R 要求"明确没有参考的也要写出来，避免下一个人以为漏查了"——**这里真的没得参考，别去找了**。它的正确性只能靠我们自己的并发测试保证（见 §9 第 1 条）。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| ERPNext SLE | 号称不可变，实际 repost 会 `UPDATE` 历史行，且级联无界 | 真的只增不改；补录用冲销流水（§2.1） |
| Odoo `stock.quant` | **没有**唯一约束，并发下产生重复行，靠"打开界面时触发"的合并任务清理，且该合并有已知合不掉的 bug | `(product_id, warehouse_id)` 唯一约束 + 条件更新，不产生重复行（§2.2） |
| Odoo `stock.quant` | 锁是 `SELECT … LIMIT 1 FOR NO KEY UPDATE SKIP LOCKED`——一个序列化令牌，不锁真正要改的行 | 直接用条件 `UPDATE` 的行锁，判定与加锁是同一条语句 |
| 两者 | "序列号数量必然为 1" **在数据库层没有任何约束**，只在业务代码里管 | 加 CHECK 约束：`tracking_type = 'serial'` 的流水行 `abs(qty) = 1`（§9 第 3 条） |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

**有，而且是本阶段发现的最强信号——三条：**

| 分歧 | 现实中的两种做法 | 判定 |
|---|---|---|
| **成本核算法** | ERPNext 按**物料**配（FIFO/LIFO/移动加权/标准成本），Odoo 按**产品类别**配（standard/fifo/average） | 总纲 R-4 已列为 `slot:costing`。**本阶段不建族**——金额整个不在本组件（在 `erp-finance`），族该建在那边或跨两边，留到出档复盘决定 |
| **补录历史的策略** | ERPNext **改写**历史（repost）；Odoo **追加**冲销层（vacuum）。两个成熟系统对同一问题给出相反答案，且各自都说得通 | ⭐ **新发现的族候选**。本阶段选"追加"，把"改写"记下来。是否真建族看有没有客户真的要求"补录后历史报表数字随之变化" |
| **拣货/发料策略** | Odoo 的 `_gather` 明确参数化了 FIFO/LIFO/FEFO/就近/整包优先 | 总纲 R-4 已列为族候选。**Odoo 自己把它做成了配置项**，这是"该建族"的强佐证——但本阶段只有一种（FIFO），不建 |

⚠️ 按 R-4 第 3 步，建族前必须确认"没有任何组件对它建依赖边"。`erp-sales` 是**对 `erp-inventory` 建了强依赖边**的，所以**这三条都不能做成 slot**——它们的正确形态是"一个组件 + 内部策略"（SOP-P）或 `customer_fork`。这个判断写进出档复盘。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | 并发预留的正确性怎么证明？没有参考实现可抄（§8） | 阶段二 Task 10 实现时 | **靠一条必须存在的 L3 并发测试**：N 个 goroutine 同时预留同一 SKU，库存只够 M 个（M<N），断言成功恰好 M 次、余额恰好归零、`-race` 无报告。这条测试挂了就是真的会超卖，**不许放宽断言**（SOP-W 的 W-5） |
| 2 | 预留要不要有 TTL（占了不用自动释放）？ | 第一个客户抱怨"库存被幽灵订单占住"时 | **阶段二不做。** 两个参考系统都没有（§8），说明它不是 ERP 的常识需求；而做了就要引入一个扫描任务 + "释放后订单怎么办"的一整套语义。现在的形态是**只能由上游显式 Cancel**——上游崩了没 Cancel 的情况，靠 §4.4.3 的定时对账发现 |
| 3 | 序列号的"数量必然为 1"用 CHECK 约束够不够？ | 阶段二迁移写完时 | 用 `CHECK`：流水行若 `serial_no = ''`（本组件文本列一律 `NOT NULL DEFAULT ''`，不用 `NULL` 表示"未填"，与全项目字符串列的约定一致）则放行，否则 `abs(qty) = 1`。⚠️ 但 `tracking_type` 在摘要副本里（§5），**数据库约束看不到它**——所以约束只能管"填了序列号的行数量必须是 1"，管不了"该填序列号的行没填"。后者只能在应用层按摘要副本判，且有一致性窗口（§5）。**这个缺口是刻意接受的，记在这里** |
| 4 | `Adjust`（盘盈盘亏）要不要走审批？ | 阶段三 `infra-workflow` 上线后 | 阶段二**直接调直接改**，只记流水与 `reason`。审批是 workflow 的活，而 workflow 严禁含业务规则（决策 27）——接法是本组件发起待办、等 `workflow.task.completed.v1` 再执行，留到阶段三 |
| 5 | 仓库主数据谁来建？契约（Task 8）没有留 `CreateWarehouse` 类接口 | 迁移写完时（Task 9） | 同 `mdm-product` 的 UOM 先例（几十行量级、客户很少新增）：**迁移播种**，不单开 CRUD。种了 `WH-EAST`/`WH-SOUTH` 两个仓库，直接对应 §1 举的"华东仓/华南仓"数据权限例子，Task 20 验 `warehouse` 维时手边就有真数据。真有客户需要频繁自建仓库/库位，再回来评估要不要开接口 |
| 6 | `Reserve` 一次接受多个 `(product, warehouse)` 项，`inventory_reservations` 该是"一行一个预留整体 + 子表存明细"还是别的形状？ | 迁移写完时（Task 9） | **选了更薄的那个：`inventory_reservations` 本身就是明细行**——一行 = 一次 `Reserve` 调用里的一个 `(product, warehouse, qty)` 项，`reservation_id`（`BIGINT`，来自 `inventory_reservation_seq` 序列，不是这张表的主键）是同一次调用里所有行共享的分组键，作为 `ReserveResponse.reservation_id` 返回给调用方。`CancelReservation`/`ConfirmIssue`/`GetReservationStatus` 按 `reservation_id` 操作这一组行，且**组内所有行的 `status` 总在同一个事务里同步迁移**，不存在组内状态不一致，所以不需要额外的"预留整体"头表。选它而不是头表+子表两张表的直接原因：设计计划 §1 给 `data_scopes` 举例时把 `warehouse_id` 列直接挂在 `inventory_reservations` 上——头表+子表的形状会让这一列落在子表而不是这张表，与已经写进 `assembly.yaml` 的声明对不上 |
| 7 | `ConfirmIssue` 一次确认整个 `reservation_id`（可能含多项），但 Task 8 契约把 `movement_id` 写成单数、`batch_no`/`serial_no` 也是单数——多项确认时装不下多条流水 id | Task 10 实现时发现 | **实现前先修的契约缺口**（不是事后打补丁）：`movement_id` → `repeated movement_ids`，一项一条流水。`batch_no`/`serial_no` **保留单数**，对整个 reservation 下所有项统一生效——多个项各自需要不同批次/序列号的情形，本阶段要求调用方拆成多个 `Reserve`/`ConfirmIssue`（各自一个 reservation_id），不在一次调用里混装。此时契约还没有任何真实调用方（`erp-sales` 要到 Task 17 才会调它），改字段形状不算破坏性变更的实际代价——留出这条记录是为了让人知道这不是疏漏 |
| 8 | `inventory_movements` 的月分区名，迁移里初始建的和后台维护任务（`monthly.go`）后续建的，是不是同一套命名规则？ | Task 10 写 `monthly.go` 时发现 | **不是，写的时候差点错过**：`monthly.go` 复用 `partition.go`（周分区）的 `ensurePartition`，分区名格式固定是 `"表名_" + from.Format("2006_01_02")`——月分区因此叫 `inventory_movements_2026_09_01`（月初那一天），不是看起来更直观的 `inventory_movements_2026_09`。迁移里最初写成了后者，两者是同一个时间范围但名字不同，`to_regclass` 查不到会让维护任务在下一次检查时尝试新建同范围分区，撞上 PostgreSQL"分区范围不许重叠"报错——**在写 `monthly.go` 时对照两处命名发现的，改的是迁移文件，不是运行时才暴露**。判据记在这里：任何"迁移建初始分区 + 后台任务建后续分区"的表，两处必须共用同一个命名函数/格式常量，不能凭直觉各写一套 |
