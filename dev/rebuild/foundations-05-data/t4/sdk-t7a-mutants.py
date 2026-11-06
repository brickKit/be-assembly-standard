TITLE = "be-sdk-go tiering (T7a): holds, approvals, destruction, its replay"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'TestTheDestruction|TestAHoldSet|TestADestruction' ./tiering/"]
MUTANTS = [
    ("tiering/destroy.go", "\t\tif _, err := tx.Exec(ctx, \"LOCK TABLE be_tier_hold IN SHARE MODE\"); err != nil {\n\t\t\treturn err\n\t\t}\n", "", "the decision locks the holds (TR14)"),
    ("tiering/destroy.go", "\t\tif why, err = c.destroyReasons(ctx, tx, unit, cur); err != nil || len(why) > 0 {", "\t\tif false {", "the decision checks again in its transaction (TR14)"),
    ("tiering/holds.go", "(h.scope_kind = 'class' AND h.scope = $2)", "(false)", "a class hold covers the unit"),
    ("tiering/holds.go", "(h.scope_kind = 'unit' AND h.scope = $1)", "(false)", "a unit hold covers the unit"),
    ("tiering/holds.go", "(h.scope_kind = 'record' AND h.scope IN (SELECT $2 || '/' || m.root_id FROM be_tier_member m WHERE m.unit::text = $1))", "(false)", "a record hold covers its unit (TR13)"),
    ("tiering/holds.go", "\"SELECT EXISTS (SELECT 1 FROM be_tier_approval WHERE withdrawn_at IS NULL AND \"+", "\"SELECT EXISTS (SELECT 1 FROM be_tier_approval WHERE \"+", "a withdrawn approval does not count"),
    ("tiering/holds.go", "\t_, _, err := sub.Check(ctx, op, authz.Facts{})\n\treturn err", "\t_ = op\n\treturn nil", "only the declared operation sets holds and approvals"),
    ("tiering/holds.go", "\"AND released_at IS NULL AND (scope = $2 OR", "\"AND (scope = $2 OR", "a hold is lifted once"),
    ("tiering/destroy.go", "\tdue := !u.anchor.IsZero() && !u.anchor.Add(time.Duration(cl.Retention.MinDays)*24*time.Hour).After(now)", "\tdue := !u.anchor.IsZero()", "the retention must have run"),
    ("tiering/destroy.go", "\t\tif cerr := p.Cancelled(context.WithoutCancel(ctx)); cerr != nil {", "\t\tif cerr := error(nil); cerr != nil {", "a decision that does not hold cancels its intent"),
    ("tiering/destroy.go", "\t\tif err := p.Effective(ctx, tx); err != nil {", "\t\tif err := error(nil); err != nil {", "the conclusion is written in the decision"),
    ("tiering/destroy.go", "\t\t_, err := tx.Exec(ctx, \"DELETE FROM be_tier_row WHERE unit::text = $1\", unit)", "\t\t_, err := tx.Exec(ctx, \"DELETE FROM be_tier_row WHERE unit::text = $1 AND false\", unit)", "the warm rows go"),
    ("tiering/destroy.go", "\t\treturn markDestroyed(ctx, tx, unit, u, basis)\n\t})", "\t\t_ = basis\n\t\treturn nil\n\t})", "the replay destroys the unit again (TR16)"),
    ("tiering/destroy.go", "\t_, err := tx.Exec(ctx, \"UPDATE be_tier_catalog SET version = version + 1\")\n\treturn err\n}\n\n// Destroy", "\treturn nil\n}\n\n// Destroy", "a destruction moves the catalog version"),
]
