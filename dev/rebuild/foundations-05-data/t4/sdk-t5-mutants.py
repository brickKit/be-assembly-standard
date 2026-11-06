TITLE = "be-sdk-go tiering (T5): copy, verify, publish, orphans, the locked bucket"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration ./tiering/"]
MUTANTS = [
    ("tiering/transfer.go", "\t\t\t\tif strconv.Itoa(len(data)) != o.Bytes || sha(data) != o.SHA256 {", "\t\t\t\tif strconv.Itoa(len(data)) != o.Bytes && sha(data) != o.SHA256 {", "an object must match its size and hash"),
    ("tiering/transfer.go", "\tif digest != m.Digest {\n\t\treturn fmt.Errorf(\"%w: the content's digest", "\tif digest == \"\" {\n\t\treturn fmt.Errorf(\"%w: the content's digest", "the content's digest is the sealed one"),
    ("tiering/transfer.go", "\t\tcase gen != claim.Generation || epoch == nil || *epoch != claim.Epoch:", "\t\tcase epoch == nil:", "a taken-over claim does not publish (TR04)"),
    ("tiering/transfer.go", "\t\tcase claim.Epoch != now:", "\t\tcase false:", "a claim of another epoch does not publish (M1)"),
    ("tiering/transfer.go", "\t\tcase state != StateSealed:", "\t\tcase state == StateDestroyed:", "only a sealed unit is published"),
    ("tiering/transfer.go", "\t\t\tif named || time.Since(o.LastModified) < window {", "\t\t\tif (named && false) || time.Since(o.LastModified) < window {", "the cleanup keeps what a manifest names"),
    ("tiering/member.go", "\t\t\tcase locked && len(cl.Erasable) > 0:", "\t\t\tcase locked && len(cl.Erasable) < 0:", "a locked bucket refuses erasable data (P15.32)"),
    ("tiering/parquet.go", "\t\treturn time.UnixMicro(v.Int64()).UTC(), nil", "\t\treturn time.UnixMilli(v.Int64()).UTC(), nil", "instants read back as written"),
]
