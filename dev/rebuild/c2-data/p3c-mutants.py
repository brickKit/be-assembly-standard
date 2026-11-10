TITLE = "erp/purchase 3.0.0 (C2 P3c): the order's lifecycle (PO01-PO06, PO10, PO11), requisitions into orders (PR06), departments"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the order routes answered CAPABILITY_UNSUPPORTED
O = "internal/orders/orders.go"
L = "internal/orders/lifecycle.go"
N = "internal/orders/lines.go"
Q = "internal/requisitions/ordering.go"
MUTANTS = [
    (N, "	if ev.supplier, err = masterdata.SupplierOf(m, ctx, in.SupplierID, in.LegalEntityID); err != nil {\n		return ev, err\n	}",
     "	ev.supplier, _ = masterdata.SupplierOf(m, ctx, in.SupplierID, in.LegalEntityID)", "PO01: the supplier may be bought from"),
    (N, "			if l.WarehouseID == nil {\n				return ev, core.Invalid(field, \"a stocked product's line names the warehouse it is received into\")",
     "			if false && l.WarehouseID == nil {\n				return ev, core.Invalid(field, \"a stocked product's line names the warehouse it is received into\")",
     "PO01: a goods line names its warehouse"),
    (N, "		b.amount = core.Times(l.Quantity, l.UnitPrice, ev.scale)", "		b.amount = core.Times(l.Quantity, l.UnitPrice, 0)",
     "PO01: the amount is rounded to the currency"),
    (L, '			Submitted: refuse("PO02", notDraft),', '			Submitted: core.ProceedCell("PO02"),', "PO02: only a draft changes"),
    (O, "				if set, err = submitted(ctx, tx, o, &d, actor); err != nil {", "				if _, err = submitted(ctx, tx, o, &d, actor); err != nil {",
     "PO03: the submitter is recorded and a policy without approval approves"),
    (O, "				if o.SubmittedBy != nil && *o.SubmittedBy == actor {", "				if false && o.SubmittedBy != nil && *o.SubmittedBy == actor {",
     "PO04: not approved by its submitter"),
    (L, '			Submitted: core.MoveCell("PO05", Draft, core.OpOrderApprove),', '			Submitted: core.MoveCell("PO05", Cancelled, core.OpOrderApprove),',
     "PO05: a rejection goes back to draft"),
    (O, "			if d.Effect == core.Move && (in.Reason == nil || strings.TrimSpace(*in.Reason) == \"\") {",
     "			if false && d.Effect == core.Move && (in.Reason == nil || strings.TrimSpace(*in.Reason) == \"\") {", "PO05: a rejection has its reason"),
    (O, "	case command == Revise && (in.SupplierID != cur.SupplierID || in.Currency != cur.Currency):",
     "	case command == Revise && in.Currency != cur.Currency:", "PO06: a revision keeps the supplier"),
    (N, "		case was.ProductID != l.ProductID:", "		case false && was.ProductID != l.ProductID:", "PO06: a kept line keeps its product"),
    (O, "		if err := header(ctx, tx, o, in, ev, true); err != nil {", "		if err := header(ctx, tx, o, in, ev, false); err != nil {",
     "PO06: a revision counts one more"),
    (L, '			Approved:  {Rule: "PO10", Effect: core.Move, To: Closed, Op: core.OpOrderEdit, Guard: GuardNothingReceiving},',
     '			Approved:  onlyApproved("PO10", "closed"),', "PO10: an approved order is closed"),
    (L, '			Closed:    refuse("PO11", "a closed order is not cancelled"),', '			Closed:    core.MoveCell("PO11", Cancelled, core.OpOrderEdit),',
     "PO11: a closed order is not cancelled"),
    (O, "				if err := requisitions.Apply(m, ctx, tx, o.LegalEntityID, takes(o.Lines, nil), actor); err != nil {",
     "				if err := requisitions.Apply(m, ctx, tx, o.LegalEntityID, nil, actor); err != nil {", "PR06: a cancelled order gives back"),
    (Q, "			if r.LegalEntityID != legalEntity || l.ProductID != t.ProductID || l.Unit != t.Unit {",
     "			if l.ProductID != t.ProductID || l.Unit != t.Unit {", "PR06: a requisition line of the same legal entity"),
    (Q, "			if r.LegalEntityID != legalEntity || l.ProductID != t.ProductID || l.Unit != t.Unit {",
     "			if r.LegalEntityID != legalEntity || l.Unit != t.Unit {", "PR06: a requisition line of the same product"),
    (Q, "			WHERE id = $1 AND ordered_qty + $2::numeric BETWEEN 0 AND quantity`", "			WHERE id = $1 AND ordered_qty + $2::numeric >= 0`",
     "PR06: never more than the line asks (the table's CHECK stays: the answer is no longer REQUISITION_LINE_NOT_USABLE)"),
    (Q, "	cmd := Reopen\n	if all {", "	cmd := Close\n	if !all {", "PR06: all ordered closes, some given back reopens"),
    ("internal/core/names.go", 'var DepartmentTables = []string{"requisition", "purchase_order"}', 'var DepartmentTables = []string{"requisition"}',
     "a department's move rewrites the orders' copied path"),
    (O, '	for _, p := range []string{"legal_entity_id", "supplier_id", "owner_id", "department_id", "state"} {',
     '	for _, p := range []string{"legal_entity_id", "owner_id", "department_id", "state"} {', "the list filters by supplier"),
]
