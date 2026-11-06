TITLE = "erp/sales 3.0.35 (T10d): the ended orders as a data class"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["bash", "-c", ". ../../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -p 1 -tags integration ./..."]
MUTANTS = [
    ("sales/orders.go", "\tif errs.Is(err, \"be\", errs.ReasonNotFound) { // not online", "\tif errs.Is(err, \"be\", errs.ReasonNotFound) && false { // not online", "an archived order is read by its key"),
    ("sales/lists.go", "\treturn fmt.Sprintf(orderFromAll, fmt.Sprintf(\"WHERE s.state NOT IN ('completed', 'cancelled') OR s.created_at > \"+\n\t\t\"now() - make_interval(days => %d)\", days))", "\treturn fmt.Sprintf(orderFromAll, fmt.Sprint(\"\", days)[:0])", "the default list's range (TR10)"),
    ("sales/tiering.go", "AND state IN ('reserving', 'committing', 'rejecting', 'cancelling')`,", "AND state IN ('committing')`,", "an open process keeps the order online (TR30)"),
    ("sales/lists.go", "\tif c.Query(\"history\") == \"true\" {", "\tif c.Query(\"history\") == \"never\" {", "the list reads the history"),
    ("sales/tiering.go", "\treturn (p.State == \"\" || p.State == state) && (p.LegalEntityID == \"\" || p.LegalEntityID == legalEntity) &&", "\treturn (p.LegalEntityID == \"\" || p.LegalEntityID == legalEntity) &&", "the history's filters select archived orders"),
    ("sales/module.go", "\tif rt.Tiering != nil { // the orders' history", "\tif rt.Tiering != nil && false { // the orders' history", "the reader is registered"),
    ("sales/tiering.go", "\tlines, err := json.Marshal(append([]map[string]any{}, a.Children[\"order_line\"]...))", "\tlines, err := json.Marshal([]map[string]any{})", "an archived order keeps its lines"),
]
