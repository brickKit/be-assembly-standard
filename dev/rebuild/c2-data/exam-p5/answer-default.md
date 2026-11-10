以下是八题的核对结果。我没改任何文件。

引用路径里，`design.md` 指 `components/erp/purchase/docs/design.md`，代码路径都在 `components/erp/purchase/` 下，`docs/zh/` 指装配项目的正式文档。

## 1. 提交后同账号批准；政策不要审批

**文档依据**
- `design.md` 的“订单的状态”：`approve` 在 `submitted` 一格是 → `approved`（PO04）。
- 规则 PO04：批准人不能是提交人，按账号。
- 规则 PO03：政策不要审批时，提交即批准，提交人即批准人，审计照写。
- 规则 PO03 同时规定：只有草稿能提交。

**代码依据**
- `orders/lifecycle.go` 的 `Lifecycle[Approve][Submitted]` 带 `GuardNotSubmitter`。
- `orders/orders.go` 的 `Action`：`o.SubmittedBy == actor` 时返回 `core.ErrApprover`。订单留在 `submitted`，也不写批准人。
- 政策不要审批时，`submitted()` 把 `d.To` 改成 `Approved`，并设 `ApprovedBy = actor`，即提交人。`Transition` 写入 `state` 和 `approved_by`，所以订单是 `approved`，审批人记提交人自己。
- `policies.NeedsApproval` 在 `Approval == "none"` 时为假。

**一致。**

- 代码里批准人检查的是 `SubmittedBy`，也就是最近一次提交人，因为修订会重写它。
- 订单已经是 `approved` 时再点“批准”，答复是忽略，不报错。

## 2. 入库成功但库存答复丢了

**文档依据**
- `design.md` 的“收货、验收与退货”：结果不明时保持 `receiving`，由恢复作业按同一身份重发；库存的流水事件也会补上已收。
- `design.md` 的“按入库事实补齐”：按流水身份去重，同一收货单的流水齐了才 `posted`。
- `receipts/AGENTS.md`：`record` 按流水身份去重，已收加、收货中减。

**代码依据**
- `receipts.CreateReceipt` 在事务里建收货单为 `receiving`，同事务加订单行的 `receiving_base_qty`，并入队 `JobReceive`。随后用 `receive` 同步调一次库存，预算 `core.SyncBudget`（`CreateReceipt` 里的 `core.SyncBudget`）。
- 答复丢了，`receive` 返回 `errUnknown`。收货单停在 `receiving`，接口答 202。
- 已收（`received_base_qty`）由两处补齐，哪个先到都行：
  - `movements.go` 的 `OnMovement`：订阅库存流水事件，只认 `kind=receipt` 且 `ref_kind=purchase_receipt`。
  - `ReceiveJob`：过了 `SyncBudget` 后按同一收货身份重发，库存幂等，答复再进 `record`。
- 补齐时 `receipt_movement` 记一条，已收加、收货中减，该收货单所有行都有流水后置 `posted`，然后调用 `orders.Progressed`。
- 答复后来又到一次：不会加两遍。`record` 先 `INSERT … ON CONFLICT (movement_id) DO NOTHING`，没插入就直接返回，不再动已收。

**一致。**

- 去重依赖一个前提：同步答复里的 `MovementIds[i]` 与事件的 `fact_id` 是同一个身份。这个前提在库存组件那边，我没查它的代码。
- 收货单已 `failed` 时流水仍会计入已收（`record` 里“the fact wins”），文档没写这一条。

## 3. 订购 100、超收 5%、已收 60、收货中 30

**文档依据**
- PO07：本次加收货中加已收不超过订购数量 ×（1+超收比例），超出整笔拒绝。
- `BRICKKIT.md`：超收答 `OVER_RECEIPT`。

**代码依据**
- `CreateReceipt` 的条件更新是 `receiving_base_qty + received_base_qty + 本次 <= base_quantity * (1 + 比例/100)`。没更新到行就返回 `core.ErrOverReceipt`，整笔事务回滚。
- 上限是 105。收 20 得 110，被拒，整笔拒绝，不建收货单。收 15 得 105，允许，答 202 还是 200 取决于库存答复。

**一致。**

- 代码比较用的是基本单位数量 `base_quantity`，文档写“订购数量”。订单单位不是基本单位时以基本单位算。

## 4. 已批准订单已收 3，改成 2 并删无进度的服务行

**文档依据**
- PO06：修订才能改已批准订单；数量不低于已收、收货中与已验收；删除的行必须没有任何进度。
- 状态表：`revise` 在 `approved` 一格是 → `submitted`，新修订；政策不要审批时 → `approved`。

**代码依据**
- 做这件事的是 `orders.ReviseOrder`，路由 `POST /api/purchase/orders/:id/revise`，见 `purchase/module.go`。
- 它调 `reviseLines`。保留行的 `UPDATE` 条件是新基本数量 ≥ `receiving_base_qty + received_base_qty`，同时新数量 ≥ `accepted_qty`、新金额 ≥ `accepted_amt`。改成 2 而已收 3，更新不到行，返回 `ErrState`，提示行低于进度。
- 整个事务回滚，同一请求里删服务行的动作也不会生效。
- 结果：不允许；订单仍是 `approved`，修订号不变。修订号从 1 起（迁移里 `revision … DEFAULT 1`），只有修订成功的 `header(..., revision=true)` 才加一。
- 如果只删服务行，且它没有进度，就会成功：状态变 `submitted`（政策不要审批时 `approved`），修订号加一。

**一致。**

- 代码多检查了已验收金额不低于已验收金额的条件，文档只写“已收、收货中与已验收”。这是细化，没有冲突。

## 5. 已完成订单退货

**文档依据**
- PO09：已批准、已完成、已关闭都能退，数量不超过该流水的净收货，超出整笔拒绝，错误码 `RETURN_EXCEEDS_RECEIPT`。
- PO12：退货使净额回落时不回到已批准，订单留在 `completed`。
- `design.md` 的“收货、验收与退货”：拒绝记 `failed`。

**代码依据**
- `Lifecycle[Return][Completed]` 是 `ProceedCell`，所以能退。
- 过账后订单仍是 `completed`：`orders.Progressed` 里 `Decide(Complete)` 在 `Completed` 一格是忽略，只发事件、版本加一。
- 一次最多退：`CreateReturn` 里每行条件更新 `returned_base_qty + 本次 <= base_quantity`，按“那条入库流水（`receipt_movement`）的收进量”算，不是按订单行。`returned_base_qty` 含退货中，超出返回 `core.ErrReturnExceeds`，整笔不建单。
- 库存拒绝：`returns.settle` 把行置 `failed`，把 `receipt_movement.returned_base_qty` 减回，订单行已收不变，不发退货事实。

**一致。**

- 要补一句：已收只在行过账时才减（`settle` 的 posted 分支），不是建单时。

## 6. 申请已全部转单关闭，订单后来被取消

**文档依据**
- PR06：转过的数量在订单取消时退回；全部转完 `closed`，退回后有行没转完又回到 `approved`。
- PR05：没转过订单的已批准申请可以取消。
- 状态表：`reopen` 在 `closed` 一格是 → `approved`。

**代码依据**
- `orders.Action` 在 `command == Cancel` 时调 `requisitions.Apply(... takes(o.Lines, nil) ...)`，把已取的数量以负数退回。
- `Apply` 里 `ordered_qty` 减回 0，再调 `settle`。不是全部转完，所以走 `Reopen`，`closed` 变 `approved`，发事件。
- 再取消这张申请：`Lifecycle[Cancel][Approved]` 的条件 `GuardNothingOrdered` 要求每行 `Ordered == "0"`。这次退回后已是 0，所以允许，申请变 `cancelled`。

**一致。**

- 如果同一申请行还有别的订单占着数量，则仍不能取消。

## 7. 匹配依据接口；退货中算不算已退

**文档依据**
- `design.md` 的“命令与查询”：匹配依据是系统面 `MatchService.Basis`，资源 `erp.purchase.system.read`。
- `BRICKKIT.md`：只对 `erp/finance` 开放；已收按流水、净额。
- `docs/zh/06-protocols/05-billing-settlement-and-payment.md`：退货之后按净数量开的票据，匹配结果只含净数量。
- `matchbasis/AGENTS.md`：退货中、失败的不算已退。

**代码依据**
- `purchase/module.go` 的 `Services`：`MatchService.Basis` 的 `Callers` 只有 `core.Finance`，销售不能调。`FactService.Read` 才是任一组件。
- `matchbasis.Basis` 返回订购、`received_base_qty`、`accepted_qty/amt`，还有每条流水的收进量与已退量。已退量是 `SUM(return_line.base_quantity) WHERE state = 'posted'`。
- `received_base_qty` 只在退货行过账时才减。所以“退货中”的数量不算已退，也不从已收里扣。

**一致。**

- 同一条流水上，“退货中”的数量已占住可退额度（`returned_base_qty`），但匹配依据里不计。这是两个不同的量，代码和说明都是这样。

## 8. 补收漏掉的计价依据；收货被拒；单价口径

**文档依据**
- `design.md` 的“事件”：增量事实不可遗漏，事实身份是收货行身份，`FactService.Read` 按身份补取。
- `design.md` 的“收货、验收与退货”：库存拒绝时同一事务发计价依据撤回事件，成本只是删掉这个来源。
- 计价依据在协议 05b：`docs/zh/06-protocols/05b-inventory-costing.md` 第 15 行写“暂估单价（税前）”，没有写按订单单位还是基本单位。事件 schema 写明 per base unit。

**代码依据**
- 补漏：成本组件调 `FactService.Read`，传收货行身份（`fact_id`）。`core.Fact` 在发事件的同一事务里存进 `purchase_fact`，`facts.Read` 按序返回，不认识的身份返回空类型。
- 收货被库存拒绝：`receipts.fail` 把收货单置 `failed`，退回收货中数量，并为每个收货行发 `valuation_basis_withdrawn`，带 `basis_fact_id`、`receipt_id`、`reason`。成本组件收到的是这条撤回事实。用户面答 409 `RECEIPT_FAILED`。
- 单价口径：`CreateReceipt` 里 `unit_price = core.Per(core.Times(行单价, 订单行数量, 12), 订单行基本数量, PriceScale)`，即订单行金额除以基本数量，每基本单位，不含税，`base_quantity` 也是基本单位。

**一致，加一处文档缺口。**

- 缺口：`design.md` 写“单价取订单行”，没说换算成基本单位。代码和 schema 是按基本单位，协议 05b 也没写口径。建议在 `design.md` 或 05b 里补一句。
- 该订单行订购单位与基本单位相同时，两个口径数值一样。

## 小结

- 八题里文档与代码都一致，没有发现冲突。
- 三处是文档写得不全：第 2 题 `failed` 收货单的流水仍计入已收，第 4 题的金额下限，第 8 题单价口径。
- 一处依赖我没核实：第 2 题的去重要求库存答复里的流水身份与事件的 `fact_id` 一致，这在库存组件那边。
