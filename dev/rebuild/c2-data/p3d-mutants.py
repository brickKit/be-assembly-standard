TITLE = "erp/purchase 3.0.0 (C2 P3d): receipts through erp/inventory (PO07, PO12), the valuation basis, the movements"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the receipt routes answered CAPABILITY_UNSUPPORTED
R = "internal/receipts/receipts.go"
V = "internal/receipts/movements.go"
MUTANTS = [
    (R, "				<= base_quantity * (1 + $3::numeric / 100)`", "				<= base_quantity * (1 + 0 * $3::numeric / 100)`",
     "PO07: the policy's over-receipt percent"),
    (R, "				WHERE id = $1 AND receiving_base_qty + received_base_qty + $2::numeric", "				WHERE id = $1 AND received_base_qty + $2::numeric",
     "PO07: what is receiving counts"),
    (R, '		if d := orders.Lifecycle.Decide(cur.State, orders.Receive); d.Effect != core.Proceed {',
     '		if d := orders.Lifecycle.Decide(cur.State, orders.Receive); false && d.Effect != core.Proceed {', "PO07: only an approved order"),
    (R, '		if !ok || ol.Kind != "goods" {', '		if !ok {', "PO07: goods lines only"),
    (R, '"unit_price": core.Per(core.Times(l.line.UnitPrice, l.line.Quantity, 12), l.line.BaseQuantity, core.PriceScale),',
     '"unit_price": l.line.UnitPrice,', "05b: the basis is per base unit"),
    (R, '			if _, err := tx.Exec(ctx, `UPDATE order_line SET receiving_base_qty = receiving_base_qty - $2::numeric\n				WHERE id = $1`, l.OrderLineID, l.BaseQuantity); err != nil {\n				return err\n			}',
     '', "a refused receipt gives back what it was receiving"),
    (R, '			if err := core.Fact(m, ctx, tx, core.ValuationWithdrawn, factID,', '			if err := core.Fact(m, ctx, tx, core.ValuationBasis+"x", factID,',
     "05b: a refused receipt's bases are withdrawn"),
    (R, '		if e, ok := refused(err); ok {', '		if e, ok := refused(err); false && ok {', "a refusal fails the receipt, not leaves it receiving"),
    (R, '		return fmt.Errorf("%w: %v", errUnknown, err)\n	}\n	if len(', '		return fail(m, ctx, r.ID, err.Error())\n	}\n	if len(',
     "an unknown answer leaves the receipt receiving"),
    (R, '		_ = receive(m, sync, id) // what is left is the work item\'s', "		_ = sync // what is left is the work item's",
     "the synchronous path sends the receipt"),
    (V, '	if err != nil || tag.RowsAffected() == 0 {\n		return err\n	}\n	var state string', '	if err != nil {\n		return err\n	}\n	var state string',
     "each movement counts once"),
    (V, '	if mv.Kind != "receipt" || mv.Reference == nil || mv.Reference.Kind != RefKind || mv.Reference.LineID == nil {\n		return nil\n	}',
     '	if true {\n		return nil\n	}', "the movement events settle a receipt (the story)"),
    ("internal/orders/progress.go", "		if done { // GuardAllDone", "		if false && done { // GuardAllDone", "PO12: an order received whole completes"),
    ("internal/orders/lifecycle.go", '			Approved:  {Rule: "PO10", Effect: core.Move, To: Closed, Op: core.OpOrderEdit, Guard: GuardNothingReceiving},',
     '			Approved:  core.MoveCell("PO10", Closed, core.OpOrderEdit),', "PO10: not closed while receiving"),
]
