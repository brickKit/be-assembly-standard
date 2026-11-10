# 参考答案（出题时写，判卷对照）

1. 被拒，`APPROVER_IS_SUBMITTER`（PO04；`orders/orders.go` 的 `Action`，`GuardNotSubmitter`）。政策不要审批：提交即 `approved`，提交人即批准人（`approved_by` 是提交人；PO03；`submitted`）。
2. 收货单 `receiving`（用户面答 202）；库存的流水事件（订阅 `erp.inventory_movement.recorded.v1`）按收货行参考补齐，工作项也按同一收货身份重发；`record` 按流水身份去重，只算一次（`receipts/movements.go`）。
3. 60 + 30 + 20 = 110 > 105：整笔拒绝 `OVER_RECEIPT`；15：105 ≤ 105 允许（收货中也计入；PO07；`CreateReceipt` 的一条 `UPDATE`）。
4. 修订（`POST /orders/{id}/revise`，PO06）：保留的行数量不低于已收、收货中、已验收，2 < 3 被拒（`STATE_CONFLICT`）；删除无进度的行可以。允许的修订之后回到 `submitted`（政策不要审批时直接 `approved`），修订号加一。
5. 能（PO09：已批准、已完成、已关闭）；过账后订单留在 `completed`（PO12 的说明，不回到已批准）；上限是那条收货流水收进的减去已退与退货中的（`receipt_movement.returned_base_qty`，超出 `RETURN_EXCEEDS_RECEIPT`，不建单）；库存拒绝时该行 `failed`，数量退回流水。
6. 取消订单退回取用的数量，申请从 `closed` 回到 `approved`（PR06，`requisitions/ordering.go` 的 `settle` 与表的 `reopen`）；之后能取消吗：已批准且转过订单的不能取消（PR05 的 `GuardNothingOrdered`）——此时转过的数量已退回为 0，所以能取消。
7. 系统面 `MatchService.Basis`，只许 `erp/finance`（别的组件 `PermissionDenied`）；“已退”只算 `posted` 的退货行，退货中不算（`matchbasis.go`）。
8. `FactService.Read` 按事实身份（收货行身份）读回（事实存在 `purchase_fact`）；收货被拒时发计价依据的撤回 `erp.purchase_receipt.valuation_basis_withdrawn.v1`；单价不含税、按基本单位（`unit_price` × 订单数量 ÷ 基本单位数量）。
