TITLE = "be-sdk-go alpha.116 (T11a, T11d): the daily orphan cleanup, an erasure voiding the exports"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/", "./internal/host/", "./launcher/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1 && go test -count=1 -tags integration "
        "-run 'TestTheDailyCleanupRemovesEveryUnitsOrphans|TestAnErasureVoidsTheExports|TestOnlyTheCurrentClaimPublishes|"
        "TestAThawedUnitReadsFromItsCopy' ./tiering/ && go test -count=1 -tags integration -run TestAComponentWithClassesServes ./launcher/"]
MUTANTS = [
    ("tiering/transfer.go", "\t\t\tif slices.ContainsFunc(named[u], func(p string) bool { return strings.HasPrefix(rest, p) }) ||",
     "\t\t\tif false ||", "an object a manifest names is never an orphan"),
    ("tiering/transfer.go", "\t\t\t\ttime.Since(o.LastModified) < window {", "\t\t\t\tfalse {", "an orphan goes only past the window"),
    ("tiering/transfer.go", "\"AND ($2 = '' OR r.unit::text = $2) AND r.version >= 0 AND r.version <> u.manifest_version + 1 \"+",
     "\"AND ($2 = '' OR r.unit::text = $2) AND r.version >= 0 \"+", "the rows of the version a transfer writes stay"),
    ("tiering/transfer.go", "\t\t\t\tif !cl.Tierable() {\n\t\t\t\t\tcontinue\n\t\t\t\t}\n\t\t\t\tn, err := c.cleanOrphans(ctx, name, \"\", window)",
     "\t\t\t\tif cl.Tierable() {\n\t\t\t\t\tcontinue\n\t\t\t\t}\n\t\t\t\tn, err := c.cleanOrphans(ctx, name, \"\", window)", "the daily job cleans every tierable class"),
    ("internal/host/build.go", "catalog.EraseJobOf(m.Logger),\n\t\t\tcatalog.CleanupJob(m.Logger)} {", "catalog.EraseJobOf(m.Logger)} {",
     "the host runs the cleanup job"),
    ("tiering/erase.go", "\"UPDATE be_tier_export SET expires_at = now() WHERE class = $1 AND state = 'done' \"+",
     "\"UPDATE be_tier_export SET expires_at = now() WHERE class = $1 AND state = 'none' \"+", "a finished export expires with an erasure"),
    ("tiering/erase.go", "\t_, err := tx.Exec(ctx, \"UPDATE be_tier_export SET erased_at = now() WHERE class = $1 AND state = 'pending'\", class)",
     "\tvar err error", "a pending export is marked"),
    ("tiering/erase.go", "\t\t} else if err := VoidExports(ctx, tx, cl.Name); err != nil {", "\t\t} else if err := error(nil); err != nil {",
     "an erasure of a released unit voids the exports"),
    ("tiering/history.go", "\"expires_at = now() + make_interval(secs => $4) WHERE id = $1 AND state = 'pending' AND erased_at IS NULL\",",
     "\"expires_at = now() + make_interval(secs => $4) WHERE id = $1 AND state = 'pending'\",", "a marked export does not finish"),
    ("tiering/history.go", "\t\t\t_, err := tx.Exec(ctx, \"UPDATE be_tier_export SET erased_at = NULL WHERE id = $1\", id)\n\t\t\treturn err",
     "\t\t\treturn nil", "the next attempt clears the mark"),
]
