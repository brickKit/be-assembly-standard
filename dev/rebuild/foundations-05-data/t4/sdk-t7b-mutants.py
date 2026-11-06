TITLE = "be-sdk-go tiering (T7b): erasure in every state, its hold and its replay"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'Erase|Erasure|TestACanonicalRow' ./tiering/"]
MUTANTS = [
    ("tiering/erase.go", "\t\tif erase {\n\t\t\tfor col := range row {", "\t\tif false {\n\t\t\tfor col := range row {", "the archived copy is erased"),
    ("tiering/erase.go", "\t\tmine := fmt.Sprint(a.Root[cl.Root.PK]) == root", "\t\tmine := true", "only the asked aggregate is erased"),
    ("tiering/erase.go", "\t\tif claim.State == StatePublished { // its online rows", "\t\tif false { // its online rows", "a published unit's online rows are erased too"),
    ("tiering/erase.go", "\t\tif _, err := tx.Exec(ctx, \"DELETE FROM be_tier_thaw WHERE unit::text = $1\", unit); err != nil {", "\t\tif _, err := tx.Exec(ctx, \"SELECT 1 WHERE $1 = ''\", unit); err != nil {", "the thawed copy is dropped"),
    ("tiering/erase.go", "\tcase holds > 0 && !redo:", "\tcase holds > 1000 && !redo:", "a held erasure writes no intent"),
    ("tiering/erase.go", "\t\tif n, err := holdsOn(ctx, tx, unit, class); err != nil || n > 0 {", "\t\tif n, err := holdsOn(ctx, tx, unit, class); err != nil || n > 1000 {", "the publish checks the holds again (TR15)"),
    ("tiering/erase.go", "\t\tif _, err := tx.Exec(ctx, \"LOCK TABLE be_tier_hold IN SHARE MODE\"); err != nil {\n\t\t\treturn err\n\t\t}\n\t\tif n, err", "\t\tif n, err", "the publish locks the holds"),
    ("tiering/erase.go", "\"UPDATE be_tier_unit SET digest = $2 WHERE id::text = $1 AND state = 'sealed'\"", "\"UPDATE be_tier_unit SET digest = digest WHERE id::text = $1 AND state = 'sealed' AND $2 <> ''\"", "a sealed unit's digest is computed again (TR27)"),
    ("tiering/transfer.go", "\t\tcase digest != claim.Was || m.Digest != claim.Digest:", "\t\tcase m.Digest != claim.Digest:", "a changed content refuses the publish (TR27)"),
    ("tiering/transfer.go", "\"UPDATE be_tier_unit SET route = $2, manifest_version = $3, digest = $4, \"+", "\"UPDATE be_tier_unit SET route = $2, manifest_version = $3, digest = digest, \"+", "a new version records its digest"),
    ("tiering/erase.go", "\t_, err = c.Enqueue(ctx, tx, EraseJob, map[string]string{\"class\": class, \"root\": root, \"basis\": basis})\n\treturn err", "\t_ = basis\n\treturn nil", "a replayed erasure is redone (P15.30)"),
    ("tiering/erase.go", "\t\treturn p.Effective(ctx, tx)", "\t\treturn nil", "the conclusion is written in the publish"),
    ("tiering/erase.go", "\t\terr = errors.Join(err, p.Cancelled(context.WithoutCancel(ctx)))", "\t\terr = errors.Join(err)", "an erasure that does not happen cancels its intent"),
    ("tiering/erase.go", "\tclaim, err := c.claim(ctx, unit, StatePublished, StateReleased)", "\tclaim, err := c.claim(ctx, unit, StatePublished)", "a released unit is erased too"),
    ("tiering/rows.go", "\t\t\treturn int16(n), nil", "\t\t\treturn n, nil", "a canonical int2 is written as one"),
]
