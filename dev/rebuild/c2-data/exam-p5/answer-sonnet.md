以下逐题核对。路径都在 `components/erp/purchase/` 下，`docs/zh/` 指装配项目的正式文档。我只读了文件，没有改任何东西，也没有运行测试。

## 1. 提交人自己批准；政策不要审批

**文档依据**
- `docs/design.md` 的“订单的状态”：`approve` 在 `submitted` 格是 → `approved` PO04；PO04 写批准人不能是提交人（按账号）。
- `docs/design.md` 的 PO03：政策不要审批时直接批准，提交人即批准人，审计照写。
- `BRICKKIT.md` 组件定位：审批人不能是提交人，法人政策可以不要审批。
- `internal/orders/AGENTS.md` 写 `GuardNotSubmitter`、`Action`、`submitted`（政策不要审批时直接批准）。

**代码依据**
- 同账号批准：`internal/orders/orders.go` 的 `Action` 在 `GuardNotSubmitter` 分支里，`*o.SubmittedBy == actor` 就返回 `core.ErrApprover`。它的原因码是 `APPROVER_IS_SUBMITTER`，HTTP 409（`internal/core/rules.go`）。订单留在 `submitted`，没有任何改动。
- 政策不要审批：`Action` 在提交时进入 `GuardPolicy` 分支，调 `submitted()`。`submitted()` 查 `policies.Of(...).NeedsApproval()`，为否就把目标状态改成 `Approved`，并设 `ApprovedBy = actor`。`Transition` 的 SQL 在 `Unapprove` 为真时把 `approved_by` 写成这个 actor，`submitted_by` 也是它。
- 结果：订单状态是 `approved`，审批人和提交人都是提交人本人。

**一致**

## 2. 库存已入库但答复丢了

**文档依据**
- `docs/design.md` 的“收货、验收与退货”：结果不明时保持 `receiving`，恢复作业按同一身份重发；库存的流水事件也会补上已收；同一收货单的流水齐了，收货单 `posted`。
- 同页“已收数量只来自入库流水”。
- `internal/receipts/AGENTS.md` 的“怎样走”：`record` 按流水身份去重。
- `BRICKKIT.md`：应答丢了，按库存的流水事件补齐。

**代码依据**
- 状态：`internal/receipts/receipts.go` 的 `receive` 对不明错误返回 `errUnknown`。`refused()` 只把库存域的 FailedPrecondition、AlreadyExists、InvalidArgument、NotFound、PermissionDenied 算作拒绝。收货单停在 `receiving`，用户面答 202。
- 补齐有两条路，都进 `internal/receipts/movements.go` 的 `record`：
  - 事件：`OnMovement` 只认 `kind=receipt` 且 `ref_kind=purchase_receipt` 的流水。
  - 工作项：`JobReceive`（`ReceiveJob`）在 3 秒同步窗口（`core.SyncBudget`）之后，按同一收货身份重发，`MaxAttempts` 不限，直到库存答复。
- 谁先到，谁来补齐已收：`record` 里 `received_base_qty += qty`、`receiving_base_qty -= base`，并在每行都有流水时把收货单置 `posted`。
- 不会加两遍：`record` 先 `INSERT INTO receipt_movement ... ON CONFLICT (movement_id) DO NOTHING`，没有新插入就直接返回。

**一致**

## 3. 订购 100、超收 5%、已收 60、收货中 30

**文档依据**
- `docs/design.md` 的 PO07：本次加收货中加已收不超过订购数量乘（1 + 超收比例），超出整笔拒绝。
- `internal/receipts/AGENTS.md`：同一条 `UPDATE` 判断，超出答 `OVER_RECEIPT`。

**代码依据**
- `CreateReceipt` 里的 `UPDATE order_line ... WHERE receiving_base_qty + received_base_qty + $2 <= base_quantity * (1 + $3/100)`，没有更新到行就返回 `core.ErrOverReceipt`（409）。
- 收 20：60 + 30 + 20 = 110，大于 105，整笔拒绝，不建收货单。
- 收 15：105，等于上限，允许。
- 比较用的是基本单位数量 `base_quantity`；文档说的是“订购数量”，这题没有单位换算，所以结果一样。

**一致**

## 4. 已收 3 的行改成 2，并删另一条无进度的服务行

**文档依据**
- `docs/design.md` 的 PO06：已批准订单只能修订，数量不低于已收、收货中与已验收；删除的行必须没有任何进度。
- 订单状态表：`edit` 在 `approved` 拒绝，`revise` 在 `approved` 是 → `submitted`，政策不要审批时 → `approved`。

**代码依据**
- 做这件事的操作是 `POST /api/purchase/orders/:id/revise`（`purchase/module.go`），处理函数是 `orders.ReviseOrder`，它调 `reviseLines`。
- 保留的行：`UPDATE order_line ... WHERE $6 >= receiving_base_qty + received_base_qty AND $3 >= accepted_qty AND $8 >= accepted_amt`。改成 2 低于已收 3，没有更新到行，返回 `ErrState`（409）。
- 整个事务回滚，服务行的删除也不会发生。
- 结果：不被允许。订单仍是 `approved`，修订号不变。`header()` 的 `revision + 1` 与 `Transition` 都没有执行。
- 若成功，状态是 `submitted`（政策不要审批时是 `approved`），修订号加 1。

**一致**

## 5. 已完成订单退货

**文档依据**
- `docs/design.md` 的订单状态表与 PO09：`approved`、`completed`、`closed` 都允许退货。
- PO12：退货使净额回落时不回到 `approved`，订单留在 `completed`。
- PO09：数量不超过该流水的净收货，在建退货单的事务里先扣，超出整笔拒绝（`RETURN_EXCEEDS_RECEIPT`），库存出库时再核对一次。
- `internal/returns/AGENTS.md`：库存拒绝时数量退回流水。

**代码依据**
- 能退：`orders/lifecycle.go` 里 `Return` 在 `Completed` 是 `ProceedCell`；`CreateReturn` 检查的是 `Decide(...).Effect != core.Proceed`。
- 退货过账：`settle` 调 `orders.Progressed`。该函数里 `Decide(Completed, Complete)` 是 `Ignore`，所以订单留在 `completed`，没有回到 `approved`。
- 上限：按单条入库流水计。`UPDATE receipt_movement SET returned_base_qty = returned_base_qty + $2 WHERE ... returned_base_qty + $2 <= base_quantity`。`returned_base_qty` 同时含退货中和已退。超出返回 `ErrReturnExceeds`，整笔回滚，不建单。
- 库存拒绝：`settle(..., "", problem)` 把退货行置 `failed`，并 `returned_base_qty -= 数量`，订单行已收不变。

**一致**

## 6. 申请已关闭，后来订单取消

**文档依据**
- `docs/design.md` 的申请状态表与 PR06：全部转完 `closed`；订单取消、删行或改小时退回；退回后有行没转完，又回到 `approved`。
- PR05：只有草稿、待审批、没转过订单的已批准能取消。表里 `closed` 的 `cancel` 是拒绝。
- `internal/requisitions/AGENTS.md`：`Apply` 里写了全部转完关闭、退回后重开。

**代码依据**
- 订单取消：`orders.Action` 在 `command == Cancel` 时调 `requisitions.Apply(..., takes(o.Lines, nil), ...)`，给回的数量是负数。
- 申请重开：`ordering.go` 的 `settle` 在不是全部转完时发 `Reopen`，`Closed` 一格是 `Move → Approved`（`GuardNotAllOrdered`）。申请回到 `approved`，`ordered_qty` 退回。
- 还能不能取消：回到 `approved` 后，`GuardNothingOrdered` 检查每行 `Ordered != "0"`。本题只有一张订单取走全部 10 个，退回后 `ordered` 为 0，所以可以取消。若还有别的订单占着数量，则拒绝。申请在 `closed` 的那段时间，取消是拒绝。

**一致**

## 7. 财务查订购、已收、已验收；销售能不能调；“退货中”算不算已退

**文档依据**
- `BRICKKIT.md` 契约索引：`MatchService/Basis` 只对 `erp/finance` 开放，按订单或订单行取订购、已收（按流水，净额）、已验收。
- `internal/matchbasis/AGENTS.md`：每条流水已过账的退货量，退货中、失败的不算。

**代码依据**
- 接口：`purchase/module.go` 的 `Services` 注册 `MatchService.Basis`，`Callers: []string{core.Finance}`，其他调用方在系统面被拒。`FactService.Read` 才是任一组件可调。
- 内容：`internal/matchbasis/matchbasis.go` 的 `Basis` 返回每行的订购数量、`received_base_qty`、`accepted_qty`、`accepted_amt`，以及每条流水的已收和已退。
- 已退：子查询 `sum(r.base_quantity) FROM return_line WHERE ... state = 'posted'`，所以“退货中”不算。
- 注意：行上的 `received_base_qty` 也是净额，它只在退货过账时减少，“退货中”同样不算。

**一致**

## 8. 成本漏收计价依据事件

**文档依据**
- `BRICKKIT.md` 与 `docs/design.md`：`FactService.Read` 按事实身份补取，事实身份是收货行身份。
- `docs/design.md` 收货一节：库存拒绝时收货单 `failed`，同事务发布每行的计价依据撤回，成本只是删掉这个来源。
- `docs/zh/06-protocols/05-billing-settlement-and-payment.md` 的共同规则：产生方提供按事实身份的查询。
- `docs/zh/06-protocols/05b-inventory-costing.md`：计价依据撤回会撤掉该来源。
- 契约 `erp.purchase_receipt.valuation_basis.v1.schema.json`：`unit_price` 是“net of tax, per base unit”。

**代码依据**
- 补取：成本调 `FactService.Read`，传收货行 ID，即 `fact_id`（`internal/facts/facts.go`）。事实由 `core.Fact` 在发布它的同一事务里存进 `purchase_fact`。
- 库存拒绝：`receipts.go` 的 `fail` 把收货单置 `failed`，退回收货中的数量，每行发一条 `valuation_basis_withdrawn`。它带新的随机 `fact_id` 和 `basis_fact_id`。
- 成本会收到：先前的计价依据事件（若漏了就用 `Read` 补），再加这条撤回事件。库存没有入库流水。
- 单价：`CreateReceipt` 里是 `Per(Times(单价, 订单行数量), 订单行 base_quantity, PriceScale)`，也就是订单金额除以基本单位数量，按基本单位计价，不是订单单位。

**一致**，但有两处空白：
- `design.md` 和 `BRICKKIT.md` 没有明说计价依据的单价是按基本单位，只有契约 schema 和 `internal/receipts/AGENTS.md` 写了。
- 撤回事实的 `fact_id` 是新生成的随机值，没有按 `basis_fact_id` 查撤回的接口。若成本既漏了计价依据又漏了撤回，只能靠 `Read` 取到那条计价依据，补不到撤回。文档和代码都没有提这一点（没有）。不过这种情况下库存没有入库流水，成本也没有对应的成本层。

## 汇总

八题都一致，没有发现文档与代码相矛盾的地方。第 8 题的两处文档空白已在上面列出。
