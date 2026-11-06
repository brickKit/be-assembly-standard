TITLE = "be-sdk-go alpha.101, again the three that did not build or survived (the test strengthened)"
BUILD = ["go", "vet", "-tags", "integration", "./runprofile/"]
TEST = ["go", "test", "-count=1", "./runprofile/"]
F = "runprofile/trust.go"
MUTANTS = [
    (F, "if err == nil && h.chainHolds(chain, rv.rec.Received) == nil && verifySignature(rv.rec.Record, mustLeaf(chain)) == nil {", "if err == nil && (h.chainHolds(chain, rv.rec.Received) == nil || true) && (verifySignature(rv.rec.Record, mustLeaf(chain)) == nil || true) {", "a revocation counts only from a trusted signer"),
    (F, "if _, err := leaf.Verify(x509.VerifyOptions{Roots: pool, Intermediates: inter, CurrentTime: t,", "if _, err := leaf.Verify(x509.VerifyOptions{Roots: pool, Intermediates: inter, CurrentTime: time.Now(),", "validity at the receipt"),
    (F, "\t\t\t\t\tr.Signed = verifySignature(tr.Record, prev) == nil", "\t\t\t\t\tr.Signed = true", "a rotation needs the previous CA's signature"),
]
