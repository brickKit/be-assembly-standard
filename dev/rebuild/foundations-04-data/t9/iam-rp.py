TITLE = "infra/iam-casdoor 3.0.25 in progress (item 4 T9c): the replay of the account status and the forced logout"
BUILD = ["go", "vet", "-tags", "integration", "./iam"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
R = "iam/replay.go"
MUTANTS = [
    (R, "\tif cur == status {\n\t\treturn nil\n\t}", "\tif cur != \"\" {\n\t\treturn nil\n\t}", "a status is not re-applied"),
    (R, "\t_, err := s.change(ctx, tx, rec.Object.ID, \"forced\", \"\")\n\treturn err", "\treturn nil", "a forced logout is not re-applied"),
    (R, "\tif errors.Is(err, pgx.ErrNoRows) {\n\t\treturn \"\", fmt.Errorf(\"account %s: %w\", principal, evidence.ErrDangling)\n\t}", "\tif errors.Is(err, pgx.ErrNoRows) {\n\t\treturn \"\", nil\n\t}", "a missing account is not dangling"),
]
