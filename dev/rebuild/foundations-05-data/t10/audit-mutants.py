TITLE = "infra/audit 3.0.30 (T10c): the audit records as a data class"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["bash", "-c", ". ../../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -p 1 -tags integration -run 'TestTheAuditRecordsTier|TestAuditEndToEnd' ./audit/"]
MUTANTS = [
    ("audit/tiering.go", "WHERE m.class = $1 AND m.root_id = ANY($2) AND u.state IN ('released', 'destroyed')`", "WHERE m.class = $1 AND m.root_id = ANY($2) AND u.state IN ('released', 'destroyed') AND false`", "a record sent again after its release is looked up in the archive"),
    ("audit/audit.go", "\tif errors.Is(err, pgx.ErrNoRows) && arch != nil {", "\tif errors.Is(err, pgx.ErrNoRows) && arch != nil && false {", "the archived copy answers the receipt"),
    ("audit/chain.go", "\t\tif first && next != stored && archived {", "\t\tif first && next != stored && archived && false {", "the chain goes on from the first online record"),
    ("audit/chain.go", "\t\tif first && next != stored && archived {", "\t\tif first && next != stored && (archived || true) {", "the chain starts mid-way only when records were released"),
    ("audit/records.go", "\t\tif gone {", "\t\tif gone && false {", "the recovery's list refuses a range into the archive"),
    ("audit/tiering.go", "\t\t\treturn err == nil && json.Unmarshal(rec, &op) == nil && op.Operation == p.Operation", "\t\t\treturn err == nil && json.Unmarshal(rec, &op) == nil", "the history's operation filter selects archived records"),
    ("audit/audit.go", "\tif c.Query(\"history\") == \"true\" && m.rt.Tiering != nil {", "\tif c.Query(\"history\") == \"never\" && m.rt.Tiering != nil {", "the query reads the history"),
    ("audit/audit.go", "\t\t\tif rt.Tiering != nil { // the history of the records", "\t\t\tif rt.Tiering != nil && false { // the history of the records", "the reader is registered"),
]
