TITLE = "infra/iam-casdoor 3.0.33: the status record names its evidence record (09a, signal_ref across a recovery)"
BUILD = ["go", "vet", "-tags", "integration", "./iam/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
MUTANTS = [
    ("iam/accountops.go", "\t\tif version, err = s.changeEv(ctx, tx, principal, reason, \"\", confirmation, evidenceID); err != nil {", "\t\tif version, err = s.changeEv(ctx, tx, principal, reason, \"\", confirmation, evidenceID[:0]); err != nil {", "an operation's status names its evidence"),
    ("iam/replay.go", "reasonFor(status), \"\", \"\", rec.ID)", "reasonFor(status), \"\", \"\", \"\")", "a replayed status names the original record"),
    ("iam/store.go", "\tif evidenceID != nil {\n\t\trec[\"evidence\"] = *evidenceID\n\t}", "\tif evidenceID != nil && false {\n\t\trec[\"evidence\"] = *evidenceID\n\t}", "the record carries it"),
]
