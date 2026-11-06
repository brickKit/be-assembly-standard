TITLE = "be-ops alpha.14: the trust domain's issuer (P12.24-P12.27, A148)"
BUILD = ["go", "vet", "./internal/trust/"]
TEST = ["go", "test", "-count=1", "./internal/trust/"]
MUTANTS = [
    ("internal/trust/trust.go", "\tif _, err := i.Profile.AppendWith(ctx, runprofile.KindTrustCredential, body, caKey, [][]byte{ca.Raw}); err != nil {\n\t\treturn \"\", fmt.Errorf(",
     "\tif _, err := i.Profile.AppendWith(ctx, runprofile.KindTrustCredential, body, caKey, [][]byte{ca.Raw}); err != nil {\n\t\t_ = fmt.Errorf(", "a credential is published only once its record is taken"),
    ("internal/trust/trust.go", "\tif body, err = runprofile.Accept(body, key); err != nil {", "\tif false {", "a rotation carries the next CA's acceptance"),
    ("internal/trust/trust.go", "\t\tif err := i.removeFromBundle(fp); err != nil {\n\t\t\treturn err\n\t\t}\n\t\tif runprofile",
     "\t\tif runprofile", "a revoked CA leaves the trust root at once"),
    ("internal/trust/trust.go", "\t\tif serr := i.spool(p); serr != nil {", "\t\tif serr := error(nil); serr != nil {", "a record not taken waits in pending"),
    ("internal/trust/trust.go", "\t\tif err := os.Remove(f); err != nil {\n\t\t\treturn n, err\n\t\t}\n", "", "a flushed record leaves pending"),
    ("internal/trust/trust.go", "\t\tDNSNames: []string{identity.DNSName(i.Deployment, component)}, NotBefore", "\t\tNotBefore", "the credential carries the derived DNS name"),
    ("internal/trust/trust.go", "\t\t\t\tif err := os.Rename(f, f+\".revoked\"); err != nil {", "\t\t\t\tif err := error(nil); err != nil {", "revoking the current CA leaves none"),
    ("internal/trust/trust.go", "\tif err := i.addToBundle(cert); err != nil {\n\t\treturn err\n\t}\n\ti.say(\"✓ CA %s → %s", "\ti.say(\"✓ CA %s → %s", "the next CA joins the trust root"),
    ("internal/trust/trust.go", "\tif runprofile.Fingerprint(cur.Raw) == fp {\n\t\treturn errors.New(\"that is the current CA: rotate first\")", "\tif false {\n\t\treturn errors.New(\"that is the current CA: rotate first\")", "the current CA is not retired"),
]
