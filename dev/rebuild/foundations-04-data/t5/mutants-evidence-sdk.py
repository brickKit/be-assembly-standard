TITLE = "be-sdk-go alpha.78 in progress (item 4 T5b, second round: the reflected mutant rewritten to build): evidence (P12.15-P12.18), go test -tags integration ./evidence/"
BUILD = ["go", "vet", "-tags", "integration", "./evidence"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./evidence/"]
E, X = "evidence/evidence.go", "evidence/transfer.go"
MUTANTS = [
    (E, "\tif w.Alert != nil && w.Alert.Alert(ctx, rec) {", "\tif false && w.Alert != nil && w.Alert.Alert(ctx, rec) {", "a failed intent does not go to the alert channel"),
    (E, "\t\tc, cancel := context.WithTimeout(context.WithoutCancel(ctx), IntentTimeout)\n\t\tst, err := w.Store.Append(c, []Sealed{s})", "\t\tc, cancel := context.WithCancel(ctx)\n\t\tst, err := w.Store.Append(c, []Sealed{s})", "the intent waits for the store without a limit"),
    (E, "\tw.log().Error(\"an intent reached neither the evidence store nor the alert channel\", \"event\", \"evidence_double_failure\",", "\tw.log().Error(\"an intent reached neither the evidence store nor the alert channel\", \"event\", \"x\",", "the double failure is not logged as such"),
    (E, "\tif _, err := tx.Exec(ctx, `INSERT INTO be_change_history (evidence_id, object_type, object_id, version_before, epoch,", "\tif _, err := tx.Exec(ctx, `SELECT $1::text, $2::text, $3::text, NULLIF($4, ''), $5::text, $6::bigint WHERE false AND true IN (SELECT (evidence_id, object_type, object_id, version_before, epoch,", "no change history row"),
    (E, "\tif err := tx.QueryRow(ctx, \"SELECT last_seq FROM be_evidence_counter FOR UPDATE\").Scan(&last); err != nil {", "\tif err := tx.QueryRow(ctx, \"SELECT last_seq FROM be_evidence_counter\").Scan(&last); err != nil {", "the commit sequence is taken without the counter's lock"),
    (E, "\t\treturn p.w.queue(ctx, tx, p.w.record(p.ID, p.category, \"cancelled\", p.subject, p.obj, p.change, nil))", "\t\treturn p.w.queue(ctx, tx, p.w.record(p.ID, p.category, \"cancelled\", p.subject, p.obj, p.change, &position{epoch: \"1.1\", seq: 1}))", "a cancelled conclusion carries a position"),
    (E, "\tif errors.Is(err, pgx.ErrNoRows) {\n\t\treturn false, nil\n\t}", "\tif errors.Is(err, pgx.ErrNoRows) {\n\t\treturn true, nil\n\t}", "everything counts as reflected"),
    (X, "\t\t\trs, err := tx.Query(ctx, `SELECT ord, id, phase, record, digest FROM be_evidence_outbox WHERE stopped IS NULL", "\t\t\trs, err := tx.Query(ctx, `SELECT ord, id, phase, record, digest FROM be_evidence_outbox WHERE true", "a stopped row is sent again"),
    (X, "\t\t\t\tcase \"accepted\", \"duplicate\":", "\t\t\t\tcase \"accepted\", \"duplicate\", \"conflict\":", "a refused record is deleted"),
]
