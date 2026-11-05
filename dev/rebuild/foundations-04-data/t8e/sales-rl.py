TITLE = "erp/sales 3.0.25 in progress (item 4 T8e): aligning the department projection at once on mdm/org's newer epoch"
BUILD = ["go", "vet", "-tags", "integration", "./sales/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./sales/"]
O = "sales/orgunits.go"
MUTANTS = [
    (O, "\tif err == nil && out.Skipped == projection.NewerEpoch {\n\t\treturn m.realignSoon(ctx, tx)\n\t}", "\tif false {\n\t\treturn m.realignSoon(ctx, tx)\n\t}", "an event of a newer epoch is only skipped"),
    (O, "\t_, err = m.rt.Work.Enqueue(ctx, tx, jobRealignOrgUnits, struct{}{})", "\t_ = jobRealignOrgUnits", "the alignment is marked but never queued"),
]
