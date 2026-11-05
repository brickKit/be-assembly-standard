TITLE = "be-sdk-go alpha.96: Replays.Check (P12.20, a check for effects outside the recovery group)"
BUILD = ["go", "vet", "-tags", "integration", "./evidence/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "Replay|Check|OneWay", "./evidence/"]
F = "evidence/replay.go"
MUTANTS = [
    (F, "\t\tdone, err = Reflected(ctx, tx, r.ID)\n", "\t\t_, err = Reflected(ctx, tx, r.ID)\n", "reflected by identity first"),
    (F, "\t\t\toutcome, detail = Inconsistent, \"could not be checked: \"+err.Error()", "\t\t\toutcome, detail = Consistent, \"could not be checked: \"+err.Error()", "an error asking is inconsistent"),
    (F, "\t\tcase ok:\n\t\t\toutcome = Consistent", "\t\tcase ok || !ok:\n\t\t\toutcome = Consistent", "false is inconsistent"),
    (F, "\t\t\toutcome, detail = Inconsistent, why", "\t\t\toutcome, detail = Inconsistent, \"\"+why[:0]", "the reason is the detail"),
    (F, "\tif (replayed || checked) && r.err == nil {", "\tif replayed && checked && r.err == nil {", "one way per category"),
    (F, "\tif check := s.Replays.checks[r.Category]; check != nil {", "\tif check := s.Replays.checks[r.Category]; check != nil && false {", "a checked category is checked"),
    (F, "\t\tChange: rec.Change, At: at}, nil", "\t\tChange: rec.Change, At: at.Add(time.Hour)}, nil", "the record's time reaches the check"),
    (F, "\t\tok, why, err := f(ctx, r)\n", "\t\tvar ok bool\n\t\tvar why string\n\t\terr := s.DB.Tx(ctx, func(ctx context.Context, tx db.Tx) error { var e error; ok, why, e = f(ctx, r); return e })\n", "the check runs outside any transaction"),
]
