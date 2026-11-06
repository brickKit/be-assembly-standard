TITLE = "be-sdk-go alpha.101: the trust material's history (P12.24-P12.26)"
BUILD = ["go", "vet", "-tags", "integration", "./runprofile/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./runprofile/"]
F = "runprofile/trust.go"
MUTANTS = [
    (F, "if trusted[r.Next] && r.Signed && r.Accepted && !trusted[r.Previous] {", "if trusted[r.Next] && r.Signed && !trusted[r.Previous] {", "a rotation needs the next CA's acceptance"),
    (F, "if r.Fingerprint == fp && t.After(r.At.Add(-skew)) {", "if r.Fingerprint == fp && t.After(r.At.Add(skew)) {", "within the skew counts as after"),
    (F, "if err == nil && h.chainHolds(chain, rv.rec.Received) == nil && verifySignature(rv.rec.Record, mustLeaf(chain)) == nil {", "if err == nil {", "a revocation counts only from a trusted signer"),
    (F, "if _, err := leaf.Verify(x509.VerifyOptions{Roots: pool, Intermediates: inter, CurrentTime: t,", "if _, err := leaf.Verify(x509.VerifyOptions{Roots: pool, Intermediates: inter, CurrentTime: time.Now(),", "validity at the receipt"),
    (F, "\t\t\t\t\tr.Signed = verifySignature(tr.Record, prev) == nil", "\t\t\t\t\tr.Signed = true", "a rotation needs the previous CA's signature"),
    ("runprofile/runprofile.go", "\tif trust == nil {\n\t\treturn s.Verify(r)\n\t}", "\tif trust == nil || true {\n\t\treturn s.Verify(r)\n\t}", "ListAll reads by the history"),
]
