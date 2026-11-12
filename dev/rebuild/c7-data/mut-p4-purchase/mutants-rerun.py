TITLE = "erp/purchase 3.0.7: the four survivors after the added cases, and mutant 9 rewritten so it builds"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/receipts/receipts.go", "\t\tif err := orders.Released(m, ctx, tx, cur); err != nil {", "\t\tif err := error(nil); err != nil {", "PO07 the release check"),
    ("internal/requisitions/ordering.go", "\t\t\tif err := released(m, ctx, tx, r); err != nil {", "\t\t\tif err := error(nil); err != nil {", "PR06 the release check"),
    ("internal/orders/approval.go", "\"quantity\": l.Quantity, \"unit\": l.Unit, \"unit_price\": l.UnitPrice}", "\"quantity\": l.Quantity, \"unit\": l.Unit}", "P17.7 the digest has the unit price"),
    ("internal/orders/approval.go", "\tif in.Version != nil && *in.Version != cur.Version {\n\t\treturn core.ErrVersion.New(fmt.Sprintf(\"the order is at version %d\", cur.Version))\n\t}\n\tchoice", "\tchoice", "PO04 the old route's version"),
    ("internal/orders/orders.go", "\t\t\t\tif err := end(ctx, tx, Document(o)); err != nil {", "\t\t\t\tif err := func() error { _ = end; return nil }(); err != nil {", "PO11 cancelling withdraws"),
]
