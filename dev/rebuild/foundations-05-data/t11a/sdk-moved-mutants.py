TITLE = "be-sdk-go alpha.116 (T11a): what the long simulation found: the backup read outside a release's transaction, an erasure starting again"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1 && go test -count=1 -tags integration "
        "-run 'TestAReleaseReadsTheBackupOutsideItsTransaction|TestAnErasureStartsAgainWhenTheUnitMovesOn' ./tiering/"]
MUTANTS = [
    ("tiering/release.go", "\t\twhy, err = c.releaseReasons(ctx, tx, u, finished, backed)",
     "\t\tf2, b2, err2 := c.latestBackup(ctx)\n\t\tif err2 != nil {\n\t\t\treturn err2\n\t\t}\n\t\t_, _ = finished, backed\n\t\twhy, err = c.releaseReasons(ctx, tx, u, f2, b2)",
     "a release reads the backup before its transaction"),
    ("tiering/reroute.go", "\t\tif !haveBackup || !finished.After(createdAt) {",
     "\t\tif f2, b2, err2 := c.latestBackup(ctx); err2 != nil || !b2 || !f2.After(createdAt) || !haveBackup || !finished.After(createdAt) {",
     "an old version's release reads the backup before its transaction"),
    ("tiering/erase.go", "\t\tif !errors.Is(err, ErrStaleClaim) || attempt == eraseAttempts {", "\t\tif true {",
     "an erasure starts again when its unit moved on"),
]
