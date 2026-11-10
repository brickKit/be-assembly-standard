TITLE = "erp/inventory 3.0.37 (C2 P0b): purchase receipts and returns"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change (the test written first: the member did not start without the two methods)
P = "internal/movements/purchase.go"
MUTANTS = [
    (P, "	if was != digest {\n		return false, nil, core.ErrContent.New(", "	if false && was != digest {\n		return false, nil, core.ErrContent.New(",
     "the same ID with other content is refused"),
    (P, "		if ok, err := stock.AtLeast(ctx, tx, o.Left, qty); err != nil || !ok {",
     "		if ok, err := stock.AtLeast(ctx, tx, o.Left, \"0\"); err != nil || !ok {", "a return is at most what the receipt has left"),
    (P, "		if o.Kind != \"receipt\" {", "		if o.Kind == \"none\" {", "a return is made from a receipt"),
    (P, "		if !slices.Contains(o.Serials, s) {", "		if false && !slices.Contains(o.Serials, s) {",
     "only serial numbers the receipt received"),
    ("inventory/module.go", "		\"Receive\":   {Operation: core.OpSysReceive, Callers: []string{core.Purchase}},",
     "		\"Receive\":   {Operation: core.OpSysReceive, Callers: []string{core.Purchase, core.Sales}},", "the purchase component only"),
    ("internal/movements/movements.go", "		if lineIDs != nil {\n			line = &lineIDs[i]\n		}", "		_ = lineIDs",
     "each movement carries its receipt line"),
]
