TITLE = "erp/purchase 3.0.0 (C2 P3e): service acceptances (PO08) and purchase returns (PO09)"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the acceptance and return routes answered CAPABILITY_UNSUPPORTED
A = "internal/acceptances/acceptances.go"
R = "internal/returns/returns.go"
MUTANTS = [
    (A, "				AND accepted_qty + $2::numeric <= quantity * (1 + $4::numeric / 100)\n", "",
     "PO08: within the ordered quantity"),
    (A, "				AND accepted_amt + $3::numeric <= amount * (1 + $4::numeric / 100)`,", "				AND $3::numeric >= 0`,",
     "PO08: within the ordered amount"),
    (A, '		if !ok || ol.Kind != "service" || seen[l.OrderLineID] {', '		if !ok || seen[l.OrderLineID] {', "PO08: service lines only"),
    (A, '			a = core.Per(core.Times(q, ol.UnitPrice, 12), "1", scale)', '			a = q', "PO08: the amount at the unit price"),
    (A, '		if d := orders.Lifecycle.Decide(cur.State, orders.Accept); d.Effect != core.Proceed {',
     '		if d := orders.Lifecycle.Decide(cur.State, orders.Accept); false && d.Effect != core.Proceed {', "PO08: only an approved order"),
    (A, '				"legal_entity_id": cur.LegalEntityID, "quantity": l.Quantity, "amount": l.Amount, "currency": cur.Currency,',
     '				"legal_entity_id": cur.LegalEntityID, "quantity": l.Quantity, "amount": l.Quantity, "currency": cur.Currency,',
     "the acceptance fact carries the amount"),
    ("internal/orders/progress.go", "			ELSE accepted_qty >= quantity OR accepted_amt >= amount END)", "			ELSE false END)",
     "PO12: a service line accepted whole is done"),
    ("internal/orders/orders.go", '					if l.Receiving != "0" || l.Received != "0" || l.AcceptedQuantity != "0" || l.AcceptedAmount != "0" {',
     '					if l.Receiving != "0" || l.Received != "0" {', "PO11: an order with an acceptance is not cancelled"),
    (R, "				WHERE movement_id = $1 AND returned_base_qty + $2::numeric <= base_quantity`", "				WHERE movement_id = $1 AND $2::numeric > 0`",
     "PO09: at most what the movement has left"),
    (R, "				WHERE mv.movement_id = $1::uuid AND ol.order_id = $2`", "				WHERE mv.movement_id = $1::uuid AND $2::uuid IS NOT NULL`",
     "PO09: a movement of this order"),
    (R, '		if d := orders.Lifecycle.Decide(cur.State, orders.Return); d.Effect != core.Proceed {',
     '		if d := orders.Lifecycle.Decide(cur.State, orders.Return); false && d.Effect != core.Proceed {', "PO09: not a draft"),
    (R, "			if _, err := tx.Exec(ctx, `UPDATE order_line SET received_base_qty = received_base_qty - $2::numeric",
     "			if _, err := tx.Exec(ctx, `UPDATE order_line SET received_base_qty = received_base_qty - 0 * $2::numeric",
     "PO09: a posted return lowers the received quantity"),
    (R, "		} else if _, err := tx.Exec(ctx, `UPDATE receipt_movement SET returned_base_qty = returned_base_qty - $2::numeric",
     "		} else if _, err := tx.Exec(ctx, `UPDATE receipt_movement SET returned_base_qty = returned_base_qty - 0 * $2::numeric",
     "a refused line gives its quantity back"),
    (R, '				unknown = fmt.Errorf("%w: %v", errUnknown, err)\n				continue',
     '				err = settle(m, ctx, r, l, "", err.Error())', "an unknown answer leaves the line returning"),
    (R, '				"product_id": l.ProductID, "base_quantity": l.BaseQuantity, "business_date": r.BusinessDate,',
     '				"product_id": l.ProductID, "base_quantity": "1", "business_date": r.BusinessDate,', "the return fact carries the quantity"),
]
