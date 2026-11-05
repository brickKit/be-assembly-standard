TITLE = "be-sdk-go alpha.88 in progress (item 4 T4e): the audit gaps (AU07, AU08, AU10, AU15, AU22, AU23)"
BUILD = ["go", "vet", "-tags", "integration", "./audit/", "./authz/", "./internal/host/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./audit/", "./authz/", "./internal/host/"]
A, T, D, H = "audit/audit.go", "audit/transfer.go", "authz/defs.go", "internal/host/build.go"
MUTANTS = [
    (A, "\tr.Changes = a.mask(r)\n", "", "restricted fields kept in clear"),
    (A, "\tif err != nil || !a.Strict[r.Operation] {\n\t\treturn err\n\t}\n\treturn a.receipt(ctx, id)", "\t_ = id\n\treturn err", "a strict read released without its receipt"),
    (A, "\tif len(receipts) != 1 || receipts[0].ID != id || receipts[0].Status != \"received\" {", "\tif len(receipts) != 1 {", "a conflict taken for a receipt"),
    (A, "\tif a.Capacity > 0 && a.backlog.Load() >= a.Capacity {\n\t\treturn ErrCapacity\n\t}\n\tr.Category = SensitiveRead", "\tr.Category = SensitiveRead", "a read over capacity"),
    (D, "\tcase o.StrictAudit:\n\t\taudit = \"strict\"\n", "", "the record says required for strict"),
    (D, "\t\tif o.StrictAudit && !slices.Contains([]string{\"read\", \"special_read\", \"export\"}, o.Purpose) {", "\t\tif false {", "strict allowed for any purpose"),
    (H, "\t\t\tif f.Class == authz.Restricted {", "\t\t\tif false {", "the restricted fields not taken from the definitions"),
    (H, "\t\tif o.StrictAudit {\n\t\t\tstrict[o.Key] = true", "\t\tif false {\n\t\t\tstrict[o.Key] = true", "the strict operations not taken from the definitions"),
]
