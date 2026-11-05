TITLE = "be-ops recover in progress (item 4 T8d): steps 1-5 of a full recovery, go test -tags integration ./internal/recovery/"
BUILD = ["go", "vet", "-tags", "integration", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./internal/recovery/"]
P, R, S = "internal/recovery/project.go", "internal/recovery/recover.go", "internal/recovery/state.go"
MUTANTS = [
    (P, "\t\tif c.Schema != \"\" && c.ID != AuditID {", "\t\tif c.Schema != \"\" {", "the evidence store's database goes back too"),
    (S, "\t\tif st.State != Restoring || !done(StepRestoreDB) {", "\t\tif st.State != Restoring {", "advance before the databases went back"),
    (S, "\t\tif st.State != Frozen {\n\t\t\treturn fmt.Errorf(\"only a frozen", "\t\tif st.State == Running {\n\t\t\treturn fmt.Errorf(\"only a frozen", "abandon after the databases went back"),
    (R, "\t\t\tif len(got) > 0 && len(wrong) == 0 {", "\t\t\tif len(got) > 0 {", "a phase change does not wait for every member"),
    (R, "\tif !at.Before(t.now()) {", "\tif false {", "T may be in the future"),
    (R, "\t\tif c.ID != \"infra/authz\" {\n\t\t\tcontinue\n\t\t}", "\t\tif true {\n\t\t\tcontinue\n\t\t}", "the authorization generation stays"),
    (R, "\t\tif err == nil && !settled {", "\t\tif false && !settled {", "the redelivery does not wait for the consumers"),
    (R, "\t\t\tif err := t.DeleteStream(ctx, s); err != nil {", "\t\t\tif err := error(nil); err != nil {", "the streams are not deleted"),
]
