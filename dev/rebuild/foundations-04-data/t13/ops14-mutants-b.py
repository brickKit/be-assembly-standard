TITLE = "be-ops alpha.14: the trust domain's issuer, the two mutants rewritten to build"
BUILD = ["go", "vet", "./internal/trust/"]
TEST = ["go", "test", "-count=1", "./internal/trust/"]
MUTANTS = [
    ("internal/trust/trust.go", "\t\t\t\tif err := os.Rename(f, f+\".revoked\"); err != nil {", "\t\t\t\tif err := os.Rename(f, f); err != nil {", "revoking the current CA leaves none"),
    ("internal/trust/trust.go", "\tif runprofile.Fingerprint(cur.Raw) == fp {\n\t\treturn errors.New(\"that is the current CA: rotate first\")", "\tif runprofile.Fingerprint(cur.Raw) == \"x\" {\n\t\treturn errors.New(\"that is the current CA: rotate first\")", "the current CA is not retired"),
]
