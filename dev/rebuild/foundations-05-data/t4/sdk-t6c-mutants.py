TITLE = "be-sdk-go tiering (T6c): history reads, limits, exports"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'TestAHistory|TestColdReads|TestAnExport' ./tiering/"]
MUTANTS = [
    ("tiering/history.go", "\t\t\tif d.Visible != authz.True || d.Action != authz.True {\n\t\t\t\tcontinue\n\t\t\t}", "", "an invisible cold aggregate is left out (TR12)"),
    ("tiering/history.go", "\tif err := c.DB.Tx(ctx, func(ctx context.Context, tx db.Tx) error { return r.Online(ctx, tx, s, sub, params, emit) }); err != nil {\n\t\treturn err\n\t}", "", "the online part is read too"),
    ("tiering/history.go", "\tdefer func() { _ = c.End(context.WithoutCancel(ctx), s) }()", "", "the read's lease ends with it"),
    ("tiering/history.go", "\tcase ctx.Err() == nil && errors.Is(syncCtx.Err(), context.DeadlineExceeded):", "\tcase false:", "past the limit a read becomes an export (TR11)"),
    ("tiering/history.go", "\tcase c.StoreLocked:", "\tcase false && c.StoreLocked:", "no export to an object-locked store"),
    ("tiering/history.go", "\tcase c.Store == nil:", "\tcase false:", "no export without a store"),
    ("tiering/history.go", "\"AND principal = $2 AND (expires_at IS NULL OR expires_at > now())\"", "\"AND $2 <> '' AND (expires_at IS NULL OR expires_at > now())\"", "only the requester sees an export"),
    ("tiering/history.go", "\t\t\tif err := c.Store.Delete(ctx, g.key); err != nil {", "\t\t\tif err := error(nil); err != nil {", "an expired export's object is deleted"),
    ("tiering/history.go", "\t\tc.slots = make(chan struct{}, n)", "\t\tc.slots = make(chan struct{}, n+100)", "cold reads are bounded per member"),
    ("tiering/history.go", "\t\t\tif err != nil && run.Attempts < run.MaxAttempts {", "\t\t\tif err != nil {", "the last failed attempt records the export failed"),
    ("tiering/history.go", "\tsub := c.Subject(principal)", "\tsub := c.Subject(\"0190f3a1-0000-7000-8000-0000000000b2\")", "an export reads under its requester's authorization"),
    ("tiering/history.go", "\tif rows != nil {\n\t\tst.Rows = *rows", "\tif false {\n\t\tst.Rows = *rows", "the status says how many rows"),
]
