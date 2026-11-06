TITLE = "be-sdk-go tiering (T7b, the two rewritten): erasure in every state, its hold and its replay"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'Erase|Erasure|TestACanonicalRow' ./tiering/"]
MUTANTS = [
    ("tiering/erase.go", "\tcase holds > 0 && !redo:", "\tcase holds > 1000 && !redo:", "a held erasure writes no intent"),
    ("tiering/erase.go", "\t_, err = c.Enqueue(ctx, tx, EraseJob, map[string]string{\"class\": class, \"root\": root, \"basis\": basis})\n\treturn err", "\t_ = basis\n\treturn nil", "a replayed erasure is redone (P15.30)"),
]
