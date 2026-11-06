TITLE = "be-sdk-go alpha.99: a double failure leaves its own evidence record (P12.23, RC22)"
BUILD = ["go", "vet", "-tags", "integration", "./evidence/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "Unreachable", "./evidence/"]
F = "evidence/evidence.go"
MUTANTS = [
    (F, "\tw.doubleFailure(ctx, p, rec[\"at\"])\n", "", "the double failure is recorded"),
    (F, "map[string]any{\"record\": p.ID,\n\t\t\t\"category\": p.category, \"at\": at})", "map[string]any{\"record\": p.ID,\n\t\t\t\"category\": p.category, \"at\": at, \"termination\": p.change[\"termination\"]})", "not the lost record's change"),
    (F, "const DoubleFailure = \"evidence_double_failure\"", "const DoubleFailure = \"security_tightening\"", "its own category"),
]
