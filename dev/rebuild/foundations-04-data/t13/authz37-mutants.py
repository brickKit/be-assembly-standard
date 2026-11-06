TITLE = "infra/authz 3.0.37: identity-side dispositions across a full recovery (CP73, CP102, CP107, CP112)"
BUILD = ["go", "vet", "-tags", "integration", "./authz/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TestMemberEndToEnd", "./authz/"]
MUTANTS = [
    ("authz/signal.go", "\tif rec.Evidence != \"\" {\n\t\tref = principal + \"@\" + rec.Evidence\n\t}", "\tif rec.Evidence != \"\" && false {\n\t\tref = principal + \"@\" + rec.Evidence\n\t}", "the signal is the evidence record"),
    ("authz/change.go", "\t\tif r := e.req.Release; r != nil { // a release", "\t\tif r := e.req.Release; r != nil && false { // a release", "a release's evidence carries it"),
    ("authz/replay.go", "\t\t\treturn nil, fmt.Errorf(\"no active identity-side disposition holds the signals %v yet: %w\", in.SignalRefs,\n\t\t\t\tevidence.ErrDeferred)", "\t\t\treturn nil, fmt.Errorf(\"no active identity-side disposition holds the signals %v yet: %w\", in.SignalRefs,\n\t\t\t\tevidence.ErrDangling)", "deferred while a signal is not applied"),
    ("authz/replay.go", "\tif len(in.SignalRefs) > 0 {\n\t\terr := tx.QueryRow", "\tif len(in.SignalRefs) > 0 && false {\n\t\terr := tx.QueryRow", "found by its signals, not its identity"),
]
