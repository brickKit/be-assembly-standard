TITLE = "(the ended-stream check rewritten in 3.0.27) infra/iam-casdoor 3.0.27 in progress (item 4 T9c): a full recovery's 6.6 (sessions from before end) and no token while it runs"
BUILD = ["go", "vet", "-tags", "integration", "./iam"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
S, M, X = "iam/store.go", "iam/module.go", "iam/sessions.go"
MUTANTS = [
    (S, "\t\tfor _, e := range all {\n\t\t\tif err := s.ended(ctx, tx, e.idHash); err != nil {", "\t\tfor _, e := range all {\n\t\t\tif err := error(nil); err != nil {", "the sweep's ends are not in the ended stream"),
]
