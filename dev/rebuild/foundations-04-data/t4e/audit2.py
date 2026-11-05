TITLE = "(the two that did not build, rewritten) infra/audit 3.0.20 in progress (item 4 T4e): the query audited and cut (AU13), the chain check (AU14)"
BUILD = ["go", "vet", "-tags", "integration", "./audit/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./audit/"]
A, C = "audit/audit.go", "audit/chain.go"
MUTANTS = [
    (A, "\tif err := m.rt.Audit.Read(ctx, audit.Record{Operation: OpRead,", "\tif err := func(audit.Record) error { return nil }(audit.Record{Operation: OpRead,", "the query not audited"),
    (A, "\t\t\t\"received_at\": r.ReceivedAt}, d.Fields))", "\t\t\t\"received_at\": r.ReceivedAt}, append(d.Fields, \"record\", \"received_at\")))", "every field to every reader"),
]
