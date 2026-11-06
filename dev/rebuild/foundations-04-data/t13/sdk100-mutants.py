TITLE = "be-sdk-go alpha.100: the replay answers deferred (P12.20)"
BUILD = ["go", "vet", "-tags", "integration", "./evidence/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TheOwnerReplaysItsEvidence", "./evidence/"]
F = "evidence/replay.go"
MUTANTS = [
    (F, "\t\tcase errors.Is(err, ErrDeferred):\n\t\t\toutcome, detail = Deferred, err.Error()\n\t\t\treturn errRollback\n", "", "deferred is an answer"),
    (F, "\t\t\toutcome, detail = Deferred, err.Error()\n\t\t\treturn errRollback", "\t\t\toutcome, detail = Deferred, err.Error()\n\t\t\treturn nil", "and rolls back"),
]
