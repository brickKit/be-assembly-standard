TITLE = "infra/notification 3.0.0: intents, delivery, inbox, preferences (C8 P4)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/c8work/go.work"}
MUTANTS = [
    ("internal/intents/intents.go", "SenderIsSource: parsed && in.Sender == from,", "SenderIsSource: parsed,", "NT02 the sender is the envelope's source"),
    ("internal/intents/intents.go", "\tcase Duplicate:\n\t\treturn nil\n", "\tcase Duplicate:\n\t\treturn insert(ctx, tx, in, \"pending\")\n", "P18.9 a duplicate is not delivered again"),
    ("internal/intents/intents.go", "\tcase Stale: // an older sequence of its merge key: kept only for the duplicate check (NT04)\n\t\treturn insert(ctx, tx, in, \"superseded\")", "\tcase Stale: // an older sequence of its merge key: kept only for the duplicate check (NT04)\n\t\treturn insert(ctx, tx, in, \"pending\")", "NT04 an older sequence is dropped"),
    ("internal/intents/intents.go", "\t_, err := tx.Exec(ctx, `UPDATE message SET withdrawn_at = now()", "\t_, err := tx.Exec(ctx, `UPDATE message SET withdrawn_at = withdrawn_at", "NT04 a newer sequence withdraws the messages"),
    ("internal/intents/intents.go", "\tif _, err := tx.Exec(ctx, `UPDATE collapse SET seq = $3, at = now() WHERE sender = $1 AND key = $2`, in.Sender,", "\tif _, err := tx.Exec(ctx, `UPDATE collapse SET seq = seq, at = now() WHERE sender = $1 AND key = $2 AND $3::bigint > 0`, in.Sender,", "NT04 the largest sequence is recorded"),
    ("internal/intents/intents.go", "\tif !adm.Delivers { // a withdraw intent only supersedes\n\t\treturn insert(ctx, tx, in, \"done\")\n\t}\n", "", "NT04 a withdraw intent delivers nothing"),
    ("internal/intents/intents.go", "\t_, err := m.RT.Audit.Write(ctx, tx, audit.Record{", "\t_, err := func(audit.Record) (string, error) { return \"\", nil }(audit.Record{", "NT02 each refusal's security record"),
    ("internal/intents/admit.go", "\tcase a.Kind == \"deliver\" && !a.ExpiresAfterOccurred:", "\tcase false:", "NT02 an expiry before the occurrence"),
    ("internal/delivery/route.go", "\tcase c.Mandatory:\n\t\treturn core.Written\n", "", "NT07 a mandatory category ignores the preference"),
    ("internal/delivery/delivery.go", "\t\t\tif !seen[h] {\n\t\t\t\tseen[h] = true\n\t\t\t\tprincipals = append(principals, h)\n\t\t\t}", "\t\t\tprincipals = append(principals, h)", "NT05 one delivery per principal"),
    ("internal/delivery/delivery.go", "\tcase !complete:\n", "\tcase false && !complete:\n", "NT06 an incomplete projection is not used"),
    ("internal/delivery/delivery.go", "\tcase len(holders) == 0:\n\t\treturn nil, core.Unresolvable, nil\n", "", "NT06 nobody holds it: unresolvable"),
    ("internal/delivery/delivery.go", "\texpired := !now.Before(p.ExpiresAt)", "\texpired := false", "NT05 the expiry"),
    ("internal/delivery/delivery.go", "\tif waiting {\n", "\tif false && waiting {\n", "NT05 a waiting position keeps the intent pending"),
    ("internal/inbox/inbox.go", "\t\tq := `SELECT ` + cols + ` FROM message WHERE principal = $1`", "\t\tq := `SELECT ` + cols + ` FROM message WHERE (principal = $1 OR true)`", "NT08 my messages only"),
    ("internal/inbox/inbox.go", "row := tx.QueryRow(ctx, `UPDATE message SET read_at = coalesce(read_at, now()) WHERE id = $1::uuid\n\t\t\tAND principal = $2 RETURNING", "row := tx.QueryRow(ctx, `UPDATE message SET read_at = coalesce(read_at, now()) WHERE id = $1::uuid\n\t\t\tAND $2::text IS NOT NULL RETURNING", "NT08 another one's message answers 404"),
    ("internal/inbox/inbox.go", "SET read_at = coalesce(read_at, now())", "SET read_at = now()", "NT08 the first moment stays"),
    ("internal/inbox/inbox.go", "\t\ttag, err := tx.Exec(ctx, `UPDATE message SET read_at = now() WHERE principal = $1 AND read_at IS NULL", "\t\ttag, err := tx.Exec(ctx, `UPDATE message SET read_at = now() WHERE $1::text IS NOT NULL AND read_at IS NULL", "NT08 marking all read is mine only"),
    ("internal/preferences/preferences.go", "\tcase cat.Mandatory:\n\t\treturn core.Invalid(\"category\", \"this category must be delivered: it cannot be turned off or on\")\n", "", "NT09 a mandatory category cannot be changed"),
]
