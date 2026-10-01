# 阶段 06 · 前端需求盘点（Task 16）

> 来源：spec §6（06c 前端）列出的页面与操作；对照现状：`components/frontend/standard`（apps/pc、apps/mobile）已有页面与 api 封装、各组件 `contracts/*.openapi.yaml`、`assembly.yaml`、`registry/permissions.tsv`、`components/infra/bff-mobile/contracts/schema.graphql`。
> 06b 重建各后端组件时按第二张表补接口；06c 做前端时按第一张表接线、按第三张表补菜单。
> 约定：PC 经网关直连 REST（路径前缀 `/{domain}/{name}`，authz/iam 例外）；移动端经 GraphQL BFF（`POST /graphql`）。金额数量一律 string 十进制；List 一律游标分页（`cursor` + `page_size`，无 offset）；写操作带 `idempotency_key`，改动类带 `version` 乐观锁。

## 0. 先说结论（06b 要关注的缺口）

1. **没有仪表盘聚合接口**：销售额/订单数、应收合计、库存预警、商机漏斗，全部缺失，需要在 erp-sales、erp-finance、erp-inventory、crm-opportunity 各补一个 `stats` 读端点。
2. **客户/产品没有"删"**：契约只有停用（`status` DISABLED）。建议"删 = 停用"，不做物理删除（有订单/凭证引用，物理删除违背引用完整性）。需用户在 06b/06c 前确认；本表按"停用/启用"列。
3. **选择器缺搜索**：客户、产品 List 没有关键字过滤（`q`）、产品没有 `status_filter`；建单、入库、商机建档都要选客户/产品，缺了就只能拉全量。
4. **库存没有"列出余额"与"列出仓库"**：只有按 `product_id + warehouse_id` 查单条余额。余额页、移动端库存查询、入库/调整的仓库下拉都卡在这里。
5. **赢单转订单在前端不可见**：订单没有来源商机字段，商机没有关联订单字段。前端"赢单→订单"只能提交赢单、看不到转出的订单。
6. **移动端现状没走 BFF**：`apps/mobile/src/api/*` 现在直接 REST 经网关调用 workflow、notification。BFF 目前只有 6 个只读 query，没有 mutation、没有通知、商机、库存列表。
7. **通知偏好权限键怪异**：`GET /preferences` 用的是 `infra.notification.preference.edit`（读也要编辑权限），建议读改用 `infra.notification.view`。
8. **打印模板管理前端完全没有**（现仅有送货单渲染按钮），后端接口齐全；只需确认三个模板接口的权限键落位（见 §2）。

## 1. 页面/操作 → 接口对照表

状态列：**已有** = 契约与后端路由都存在、字段够用；**缺失** = 需要 06b 新增；**需改** = 接口在但字段/参数/权限需调整。"（新）"表示需要新增的权限键。

### 1.1 PC

| 端 | 页面 | 操作 | 组件 | 接口（方法 路径） | 现状 |
|---|---|---|---|---|---|
| PC | 仪表盘 | 销售 KPI（本月订单数/销售额、趋势） | erp/sales | `GET /erp/sales/stats/summary` | 缺失 |
| PC | 仪表盘 | 应收 KPI（应收合计/已核销/账龄分桶） | erp/finance | `GET /erp/finance/ar-ledger/summary` | 缺失 |
| PC | 仪表盘 | 库存 KPI（SKU 数、可用量低于阈值的清单） | erp/inventory | `GET /erp/inventory/stats/summary` | 缺失 |
| PC | 仪表盘 | 商机漏斗（各阶段数量/加权金额） | crm/opportunity | `GET /crm/opportunity/opportunities/funnel` | 缺失 |
| PC | 客户 | 列表 + 搜索 | mdm/customer | `GET /mdm/customer/customers` | 需改（补 `q` 关键字，匹配 code/name） |
| PC | 客户 | 详情 | mdm/customer | `GET /mdm/customer/customers/{id}` | 已有 |
| PC | 客户 | 新建 | mdm/customer | `POST /mdm/customer/customers`（`mdm.customer.create`） | 已有 |
| PC | 客户 | 编辑 | mdm/customer | `PATCH /mdm/customer/customers/{id}`（`mdm.customer.update`） | 已有 |
| PC | 客户 | 删除 = 停用/启用 | mdm/customer | `POST /mdm/customer/customers/{id}/status`（`mdm.customer.set_status`） | 已有（见 §0.2，待确认语义） |
| PC | 客户 | 新增联系人 | mdm/customer | `POST /mdm/customer/customers/{id}/contacts` | 已有 |
| PC | 客户 | 编辑/删除联系人、增改开票信息 | mdm/customer | 无 | 缺失（详情页要编辑联系人与开票信息才需要；spec 未点名，列为可选） |
| PC | 产品 | 列表 + 搜索 + 状态过滤 | mdm/product | `GET /mdm/product/products` | 需改（补 `q` 匹配 sku/name、`status_filter`） |
| PC | 产品 | 新建 | mdm/product | `POST /mdm/product/products`（`mdm.product.create`） | 已有 |
| PC | 产品 | 编辑 | mdm/product | `PATCH /mdm/product/products/{id}`（`mdm.product.edit`） | 已有 |
| PC | 产品 | 删除 = 停用/启用 | mdm/product | `POST /mdm/product/products/{id}/status`（`mdm.product.edit`） | 已有（见 §0.2） |
| PC | 销售订单 | 列表（含状态/客户过滤） | erp/sales | `GET /erp/sales/orders` | 已有 |
| PC | 销售订单 | 详情 | erp/sales | `GET /erp/sales/orders/{id}` | 需改（补 `source_opportunity_id`，见 §2） |
| PC | 销售订单 | 新建（含实时试算） | erp/sales | `POST /erp/sales/orders`、`POST /erp/sales/price/dry-run`（`erp.sales.create`） | 已有（客户/产品选择器依赖上面两处 `q`） |
| PC | 销售订单 | 确认 | erp/sales | `POST /erp/sales/orders/{id}/confirm`（`erp.sales.confirm`） | 已有 |
| PC | 销售订单 | 取消 | erp/sales | `POST /erp/sales/orders/{id}/cancel`（`erp.sales.cancel`，带 `reason`） | 已有 |
| PC | 销售订单 | 发货（现有按钮） | erp/sales | `POST /erp/sales/orders/{id}/ship` | 已有 |
| PC | 销售订单 | 打印送货单 | infra/print | `POST /infra/print/render`（`infra.print.render`） | 已有 |
| PC | 库存 | 余额列表（按产品/仓库） | erp/inventory | `GET /erp/inventory/balances`（现仅单条） | 缺失（需列表形态，见 §2） |
| PC | 库存 | 仓库下拉 | erp/inventory | `GET /erp/inventory/warehouses` | 缺失 |
| PC | 库存 | 流水 | erp/inventory | `GET /erp/inventory/movements` | 已有 |
| PC | 库存 | 入库 | erp/inventory | `POST /erp/inventory/movements/receive`（`erp.inventory.receive`） | 已有 |
| PC | 库存 | 盘盈盘亏调整 | erp/inventory | `POST /erp/inventory/movements/adjust`（`erp.inventory.adjust`） | 已有 |
| PC | 财务 | 凭证列表 | erp/finance | `GET /erp/finance/entries` | 已有（补 `source_doc_id` 过滤可选） |
| PC | 财务 | 凭证详情（分录行） | erp/finance | `GET /erp/finance/entries/{id}` | 已有 |
| PC | 财务 | 应收台账（现有） | erp/finance | `GET /erp/finance/ar-ledger` | 需改（补客户名、未核销余额字段，见 §2） |
| PC | 财务 | 手工凭证 / 冲销 / 关账（spec 未要求，仅列出现状） | erp/finance | `POST /entries`、`/entries/{id}/reverse`、`/periods/{p}/close\|reopen\|lock` | 已有（本期前端不做） |
| PC | 商机 | 列表（我的/本部门视图、状态/阶段过滤） | crm/opportunity | `GET /crm/opportunity/opportunities` | 已有 |
| PC | 商机 | 阶段清单（漏斗/选择器） | crm/opportunity | `GET /crm/opportunity/stages` | 已有 |
| PC | 商机 | 详情 | crm/opportunity | `GET /crm/opportunity/opportunities/{id}` | 需改（补 `order_id`，并建议补阶段历史，见 §2） |
| PC | 商机 | 新建 / 编辑 | crm/opportunity | `POST /opportunities`、`PATCH /opportunities/{id}`（`crm.opportunity.edit`） | 已有 |
| PC | 商机 | 阶段推进 | crm/opportunity | `POST /opportunities/{id}/stage`（`crm.opportunity.edit`） | 已有 |
| PC | 商机 | 赢单（触发转订单） | crm/opportunity | `POST /opportunities/{id}/win`（`crm.opportunity.win`） | 已有 |
| PC | 商机 | 输单 | crm/opportunity | `POST /opportunities/{id}/lose`（`crm.opportunity.edit`） | 已有 |
| PC | 商机 | 赢单后跳转到生成的订单 | crm/opportunity + erp/sales | 商机 `order_id` ↔ 订单 `source_opportunity_id` | 缺失 |
| PC | 打印模板 | 列表 | infra/print | `GET /infra/print/templates`（`infra.print.template.view`） | 已有 |
| PC | 打印模板 | 详情（含内容） | infra/print | `GET /infra/print/templates/{id}` | 已有 |
| PC | 打印模板 | 保存新版本 | infra/print | `PUT /infra/print/templates/{id}`（`infra.print.template.edit`） | 已有 |
| PC | 打印模板 | 回滚 | infra/print | `POST /infra/print/templates/{id}/rollback` | 已有 |
| PC | 打印模板 | 预览 | infra/print | `POST /infra/print/templates/{id}/preview` | 已有 |
| PC | 打印模板 | 版本历史列表 | infra/print | `GET /infra/print/templates/{id}/versions` | 缺失（回滚需要先选版本） |
| PC | 通知偏好 | 读取/保存 | infra/notification | `GET`/`PUT /infra/notification/preferences` | 需改（GET 的权限键改为 `infra.notification.view`） |
| PC | 通知 | 我的通知列表（现有） | infra/notification | `GET /infra/notification/notifications` | 已有（站内已读状态需求若要做则缺 `POST .../{id}/read`，本期不做） |
| PC | 待办 | 列表/详情/同意/驳回（现有） | infra/workflow | `GET /tasks`、`/tasks/{id}`、`POST /approve`、`/reject` | 已有 |
| PC | 权限 | 角色列表/授权/用户角色（现有） | infra/authz | `/api/admin/roles*`、`/api/admin/users/{sub}/*` | 已有（无"列出权限键目录""列出用户"，见 authz.ts 注释；06c 如要下拉选择，需 authz 补 `GET /api/admin/permission-keys`，列为可选） |
| PC | 全局 | 登录/刷新/特性/我的权限 | iam-casdoor、authz | `/api/iam/token*`、`/api/tenant/features`、`/api/me/permissions` | 已有 |
| PC | 全局 | i18n（中英文） | — | 纯前端，无后端需求 | 不适用 |

### 1.2 移动 H5（经 BFF `POST /graphql`）

BFF 现状见 `contracts/schema.graphql`：只有 `customer(s)`、`product(s)`、`order`、`myOrders`、`inventoryBalance`、`myTasks` 六个只读 query。

| 端 | 页面 | 操作 | 组件 | 接口（BFF 操作 → BFF 需调用的后端） | 现状 |
|---|---|---|---|---|---|
| 移动 | 审批 | 待办列表 | bff-mobile | `query myTasks` → REST `GET /infra/workflow/tasks`（转发 Authorization） | 已有（但移动端 `api/workflow.ts` 目前绕过 BFF 直连 REST，06c 改走 BFF） |
| 移动 | 审批 | 待办详情（含审批历史） | bff-mobile | `query task(id)` → REST `GET /infra/workflow/tasks/{id}` | 缺失（schema 无 `task(id)`，无 `actions` 字段） |
| 移动 | 审批 | 同意 / 驳回 | bff-mobile | `mutation approveTask(id, comment)`、`mutation rejectTask(id, comment!)` → REST `POST /infra/workflow/tasks/{id}/approve\|reject` | 缺失（BFF 目前无 Mutation 类型；新键 `infra.bff-mobile.task.act`（新）） |
| 移动 | 通知 | 我的通知列表 | bff-mobile | `query myNotifications(cursor, pageSize)` → REST `GET /infra/notification/notifications` | 缺失（新键 `infra.bff-mobile.notification.view`（新）） |
| 移动 | 订单查询 | 订单列表（按状态）、订单详情 | bff-mobile | `query myOrders`、`query order(id)` → REST `GET /erp/sales/orders`、`/orders/{id}` | 已有（按客户过滤 `customerId` 参数缺，可选补） |
| 移动 | 库存查询 | 按产品查各仓余额 | bff-mobile | `query inventoryBalances(productId!, cursor, pageSize)` → REST `GET /erp/inventory/balances`（列表形态，依赖 erp-inventory 补接口） | 缺失（现有 `inventoryBalance(productId, warehouseId)` 必须知道仓库 id，移动端无法使用） |
| 移动 | 库存查询 | 产品搜索（按 SKU/名称找产品） | bff-mobile | `query searchProducts(keyword!, cursor)` → gRPC/REST 产品 List 的 `q` | 缺失（现有 `products(ids)` 只能按已知 id 批量取） |
| 移动 | 库存查询 | 仓库名展示 | bff-mobile | `query warehouses` → REST `GET /erp/inventory/warehouses` | 缺失 |
| 移动 | 商机速览 | 我的商机列表（`view=mine`）、详情 | bff-mobile | `query myOpportunities(cursor, pageSize, status)`、`query opportunity(id)` → REST `GET /crm/opportunity/opportunities`、`/opportunities/{id}`（含 org/owner 数据权限，必须 REST 转发，不走 gRPC） | 缺失（新键 `infra.bff-mobile.opportunity.view`（新）；schema 需新增 `Opportunity`、`OpportunityStatus`；crm-opportunity 在装配时按弱依赖裁剪字段） |
| 移动 | 登录/回调/特性/我的权限 | 同 PC | iam-casdoor、authz | 同 PC 认证接口（不经 BFF） | 已有 |
| 移动 | i18n | — | — | 纯前端 | 不适用 |

## 2. 按组件汇总：06b 需要补的接口

权限键规则：新键必须追加到 `registry/permissions.tsv`（append-only）并写进该组件 `assembly.yaml` 的 `permissions`。数据范围维度沿用该组件现有 `data_scopes`，不新增维度。

### 2.1 mdm/customer（`data_scopes: none`）

- **改 `GET /customers`**：新增 query 参数 `q`（模糊匹配 `code`、`name`，大小写不敏感，前缀优先）。权限仍 `mdm.customer.view`。BFF 的客户搜索、PC 建单客户选择器、商机建档客户选择器都用它。
- 可选：联系人 `PATCH/DELETE /customers/{id}/contacts/{contact_id}`（新键复用 `mdm.customer.update`，不新增键）、开票信息 `POST /customers/{id}/billing-infos`（同键）。spec 未点名，本期前端只做"新增联系人"，不强制。
- 待确认：删除语义（§0.2）。若用户决定要物理删除，则新增 `DELETE /customers/{id}` + 新键 `mdm.customer.delete`（新），且需先检查订单/商机/应收引用，有引用时拒绝。

### 2.2 mdm/product（`data_scopes: none`）

- **改 `GET /products`**：新增 `q`（匹配 `sku`、`name`）、`status_filter`（ACTIVE/DISABLED，同 customer 的写法）。权限 `mdm.product.view`。
- 说明：`POST /products/{id}/status` 用的是 `mdm.product.edit`，与 customer 的独立 `set_status` 键不对称。要保持两个 mdm 组件一致就新增 `mdm.product.set_status`（新）；不改也能用，仅是一致性问题，列为可选。
- 待确认：删除语义（§2.1 同）。

### 2.3 erp/inventory（数据范围：`warehouse`，`mode: in`）

- **新增 `GET /warehouses`**：返回当前用户可见的仓库（受 warehouse 维度过滤）。响应 `{ warehouses: [{ id, code, name, status }] }`。权限 `erp.inventory.view`。入库/调整/余额页的仓库下拉、移动端仓库名展示都用它。
- **新增 `GET /balances/list`**（或把 `GET /balances` 在省略 `product_id`/`warehouse_id` 时变为列表，二选一，推荐前者以免改变现有单条语义）：query `product_id?`、`warehouse_id?`、`cursor`、`page_size`；响应 `{ balances: [Balance], next_cursor }`，`Balance` 字段沿用现有（`product_id, warehouse_id, on_hand_qty, reserved_qty, available_qty, version`）。权限 `erp.inventory.view`，受 warehouse 维度过滤。
- **新增 `GET /stats/summary`**（仪表盘）：响应 `{ sku_count, total_on_hand_qty, low_stock: [{ product_id, warehouse_id, available_qty }] }`；低库存阈值先用固定配置项（如 `LOW_STOCK_THRESHOLD`，走 `rt.Config`），不新增表。权限 `erp.inventory.view`，受 warehouse 维度过滤。
- 现有 `GET /movements`、`POST /movements/receive`、`/movements/adjust` 无需改。

### 2.4 erp/sales（数据范围：`org` + `owner`）

- **改订单模型**：`Order` 增加 `source_opportunity_id`（string，空串表示手工建单）。由赢单事件消费路径写入（该路径已存在，`opportunity_won` TCC 消费），不是建单请求入参，前端不可设置。`GET /orders` 增加 query `source_opportunity_id` 过滤（商机详情反查订单用）。
- **新增 `GET /stats/summary`**（仪表盘）：query `period`（`month` 默认 / `week` / `quarter`）；响应 `{ order_count, confirmed_count, total_amount, by_day: [{ date, order_count, total_amount }], by_status: { DRAFT: n, ... } }`。权限 `erp.sales.view`，受 org/owner 维度过滤（与列表一致，视角参数沿用 `view=mine|dept`，省略默认 dept）。金额 string。
- 现有 `price/dry-run`、`create`、`confirm`、`cancel` 够用。

### 2.5 erp/finance（数据范围：`legal_entity`，`mode: in`）

- **新增 `GET /ar-ledger/summary`**（仪表盘）：响应 `{ total_receivable, total_reconciled, outstanding, aging: { d0_30, d31_60, d61_90, d90_plus } }`，可选 `customer_id`。权限 `erp.finance.view`，受 legal_entity 过滤。
- **改 `GET /ar-ledger`**：`ARLedgerEntry` 增加 `customer_name`（快照）与 `outstanding`（`amount - reconciled_amount`，服务端算，前端不自己算钱）。
- **改 `GET /entries`**：增加 query `source_doc_id`、`source_doc_type` 过滤（订单详情"查看对应凭证"可选用）。
- 凭证页要用到的 `GET /entries`、`GET /entries/{id}` 已有，无需新键。

### 2.6 crm/opportunity（数据范围：`org` + `owner`）

- **改 `Opportunity`**：增加 `order_id`（赢单转出的订单 id，未转则空串；由消费订单创建结果的事件回填，需要 erp-sales 在订单创建后发一个事件或由 crm 订阅 `erp.sales.order.created`，具体事件方案在 06b crm 计划里定，契约上只暴露字段）。
- **新增 `GET /opportunities/{id}/stage-history`**：响应 `{ history: [{ from_stage_id, to_stage_id, probability, changed_by, changed_at }] }`（组件内已有"阶段推进写历史"，只缺读接口）。权限 `crm.opportunity.view`。
- **新增 `GET /opportunities/funnel`**（仪表盘）：响应 `{ stages: [{ stage_id, stage_name, count, expected_amount, weighted_amount }] }`，只统计 OPEN；受 org/owner 过滤，`view=mine|dept` 同列表。权限 `crm.opportunity.view`。
- 其余（create/update/stage/win/lose/stages）已有。

### 2.7 infra/print

- **新增 `GET /infra/print/templates/{id}/versions`**：响应 `{ versions: [{ version, name, enabled, created_at }] }`，权限 `infra.print.template.view`。（`rollback` 需要选版本，当前只能盲填版本号。）
- 其余模板接口齐全。须确认 `preview` 用 `infra.print.template.edit`（预览发生在编辑流程里），`render` 用 `infra.print.render`；不新增键。
- 06c 注意：现在 `api/print.ts` 写死 `sales.delivery_note` 模板 id，且没有任何默认模板播种，需要 print 的种子数据里带一份。

### 2.8 infra/notification（数据范围：`owner`，`recipient_sub`）

- **改权限键**：`GET /preferences` 由 `infra.notification.preference.edit` 改为 `infra.notification.view`（读不应要编辑权限）；`PUT /preferences` 保持 `edit`。键本身不变，只调整路由绑定，不违反"已发布键名不改"。
- 本期不做站内"已读/未读"；若 06c 设计稿要未读角标，则新增 `GET /notifications/unread-count` 与 `POST /notifications/{id}/read`（权限 `infra.notification.view`，改库表需 `read_at`），先不列入必做。

### 2.9 infra/workflow、infra/authz、infra/iam-casdoor

- workflow：现有 list/get/approve/reject 满足 PC 与移动端；BFF 需要 `GET /tasks/{id}` 返回审批历史（已有 `TaskDetail`）。**无新增**。
- authz：现有满足；可选新增 `GET /api/admin/permission-keys`（权限 `infra.authz.admin`，返回聚合后的键目录 + 标题），让"给角色勾权限"从自由输入变选择器。spec 未点名，列为可选。
- iam-casdoor：无新增。

### 2.10 infra/bff-mobile（`data_scopes: none`，真实数据权限由下游 REST 判）

需要补的 GraphQL 操作（实现方式：有真实数据权限的一律 REST 转发 Authorization，沿用现有判据）：

| 操作 | 类型 | 调用 | 新权限键 | 备注 |
|---|---|---|---|---|
| `task(id: ID!): Task`（含 `actions`） | Query | REST `GET /infra/workflow/tasks/{id}` | 复用 `infra.bff-mobile.task.view` | 新增 `TaskAction` 类型 |
| `approveTask(id, comment)`、`rejectTask(id, comment!)` | Mutation | REST `POST .../approve\|reject` | `infra.bff-mobile.task.act`（新） | BFF 目前没有 Mutation 根类型；要透传幂等 |
| `myNotifications(cursor, pageSize)` | Query | REST `GET /infra/notification/notifications` | `infra.bff-mobile.notification.view`（新） | 弱依赖，未装配 notification 则字段不注册 |
| `inventoryBalances(productId!, cursor, pageSize)` | Query | REST `GET /erp/inventory/balances/list` | 复用 `infra.bff-mobile.inventory.view` | 依赖 §2.3 |
| `warehouses` | Query | REST `GET /erp/inventory/warehouses` | 复用 `infra.bff-mobile.inventory.view` | 依赖 §2.3 |
| `searchProducts(keyword!, cursor, pageSize)` | Query | 产品 List 的 `q`（走 gRPC 需 mdm-product 的 gRPC `List` 带 `q`；否则 REST） | 复用 `infra.bff-mobile.product.view` | 依赖 §2.2 |
| `myOpportunities(cursor, pageSize, status)`、`opportunity(id)` | Query | REST `GET /crm/opportunity/opportunities`（`view=mine`）、`/opportunities/{id}` | `infra.bff-mobile.opportunity.view`（新） | 依赖 crm 的 org/owner 数据权限，必须 REST 转发 |
| `myOrders` 增加 `customerId` 参数（可选） | Query 参数 | REST `GET /erp/sales/orders?customer_id=` | 复用 | 小改 |

三个新键（`infra.bff-mobile.task.act`、`infra.bff-mobile.notification.view`、`infra.bff-mobile.opportunity.view`）要追加到 `registry/permissions.tsv`，owner_component `infra/bff-mobile`。

### 2.11 新权限键汇总

| 键 | 类型 | 归属组件 | 必须/可选 |
|---|---|---|---|
| `infra.bff-mobile.task.act` | action | infra/bff-mobile | 必须 |
| `infra.bff-mobile.notification.view` | action | infra/bff-mobile | 必须 |
| `infra.bff-mobile.opportunity.view` | action | infra/bff-mobile | 必须 |
| `mdm.product.set_status` | action | mdm/product | 可选（一致性） |
| `mdm.customer.delete` | action | mdm/customer | 仅在决定物理删除时 |

PC 端新增接口全部复用已有 view 键（stats、warehouses、balances 列表、funnel、stage-history、versions 都是 `*.view`）。

## 3. 菜单现状与 06c 需要补的部分

现状：`menuRegistry.ts` 手写；各组件 `assembly.yaml` 的 `menus` 每个组件只有一条（`key/title/permission`），没有二级页面、没有图标、没有排序。

| 组件 | 现有 `menus` | 06c 需要补 |
|---|---|---|
| mdm/customer | `mdm.customer` 客户管理（`mdm.customer.view`） | 无（单页 + 详情） |
| mdm/product | `mdm.product` 产品管理（`mdm.product.view`） | 无 |
| erp/sales | `erp.sales` 销售管理（`erp.sales.view`） | 订单列表为主页；新建订单入口可作为列表页按钮，不另开菜单 |
| erp/inventory | `erp.inventory` 库存管理（`erp.inventory.view`） | 需要二级项：库存余额、库存流水（入库/调整作为页内操作，由 `erp.inventory.receive`/`adjust` 控制按钮显示） |
| erp/finance | `erp.finance` 财务管理（`erp.finance.view`） | 需要二级项：凭证、应收台账 |
| crm/opportunity | `crm.opportunity` 商机管理（`crm.opportunity.view`） | 需要二级项：商机列表、漏斗 |
| infra/print | `infra.print` 打印模板管理（`infra.print.template.view`） | 无 |
| infra/notification | `infra.notification` 我的通知（`infra.notification.view`） | 需要二级项：我的通知、通知偏好；另有 `infra.notification.admin` 排障视图无菜单项 |
| infra/workflow | `infra.workflow` 我的待办（`infra.workflow.task.view`） | 全局视图 `infra.workflow.admin` 无菜单项（现有页面也没有，不在 spec 范围） |
| infra/authz | `infra.authz` 权限与角色管理（`infra.authz.admin`） | 无 |
| integration/im-dingtalk | `integration.im` 钉钉投递排障（`integration.im.admin`） | 无前端页面，菜单项存在但 PC 没有对应路由，06c 要么补页面要么去掉菜单 |
| infra/iam-casdoor、infra/bff-mobile、frontend/standard | `menus: []` / 无 menus | 无 |
| （仪表盘） | 无 | 仪表盘是前端自带的首页，不属于任何业务组件，不进 `assembly.yaml`，由 `frontend/standard` 固定为首页；其卡片按 `erp.sales.view`、`erp.finance.view`、`erp.inventory.view`、`crm.opportunity.view` 逐卡显隐（缺哪个组件/键就不渲染那张卡） |

结论：要用 be-ops 汇总菜单取代手写 `menuRegistry.ts`，`menus` 条目格式需要扩展出可选的二级项（`items: [{ key, title, permission? }]`）和 `order`/`icon`。这是对 `assembly.yaml` schema 与 be-ops 的改动，不是 06b 后端组件的事，建议在 06c 开头先用一个 Task 定下来（涉及 `tools/be-ops` 与 14 个 `assembly.yaml`）。
