TITLE = "infra/audit 3.0.30 (T10c, the one rewritten): the audit records as a data class"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["bash", "-c", ". ../../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -p 1 -tags integration -run 'TestTheAuditRecordsTier|TestAuditEndToEnd' ./audit/"]
MUTANTS = [
    ("audit/chain.go", "\t\tif first && next != stored && archived {", "\t\tif first && next != stored && (archived || true) {", "the chain starts mid-way only when records were released"),
]
