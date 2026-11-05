TITLE = "infra/audit 3.0.20 in progress (item 4 T4e): the query audited and cut (AU13), the chain check (AU14)"
BUILD = ["go", "vet", "-tags", "integration", "./audit/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./audit/"]
A, C = "audit/audit.go", "audit/chain.go"
MUTANTS = [
    (A, "\tif err := m.rt.Audit.Read(ctx, audit.Record{Operation: OpRead,", "\tif err := error(nil); err != nil && false && m.rt.Audit.Read(ctx, audit.Record{Operation: OpRead,", "the query not audited"),
    (A, "\t\t\t\"received_at\": r.ReceivedAt}, d.Fields))", "\t\t\t\"received_at\": r.ReceivedAt}, []string{\"id\", \"source\", \"record\", \"received_at\"}))", "every field to every reader"),
    (C, "\t\tif _, err := records.Open(\"be.audit.record\", raw, digest); err != nil {", "\t\tif _, err := records.Open(\"be.audit.record\", raw, digest); err != nil && false {", "a record changed in place passes"),
    (C, "\t\tif chain != stored {", "\t\tif chain != stored && false {", "the chain not followed record by record"),
    (C, "\tif chain != headChain {", "\tif false {", "the head not compared"),
    (C, "\t\tif _, err := tx.Exec(ctx, `INSERT INTO audit_chain_break", "\t\tif _, err := tx.Exec(ctx, `SELECT $1::text, $2::text, $3::bigint, $4::text WHERE false AND EXISTS (SELECT 1 FROM audit_chain_break", "a break not recorded"),
]
