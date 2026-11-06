TITLE = "be-sdk-go tiering (T6a-b): release, reads, snapshot, thaw"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration ./tiering/"]
MUTANTS = [
    ("tiering/barrier.go", "AND coalesce(current_setting('be.tier_unit', true), '') <> uid THEN", "AND coalesce(current_setting('be.tier_unit', true), '') = '' THEN", "only the named unit is let through"),
    ("tiering/release.go", "\"SELECT count(*) FROM be_tier_lease WHERE catalog_version < $1 AND expires_at > now()\"", "\"SELECT count(*) FROM be_tier_lease WHERE catalog_version < $1 AND expires_at > now() - interval '1 day'\"", "an expired lease does not hold the release"),
    ("tiering/release.go", "\t\tbacked = ok && finished.After(u.publishedAt)", "\t\tbacked = ok && !finished.IsZero()", "the backup must be after the publish"),
    ("tiering/release.go", "\t\t\tif left > 0 { // children first", "\t\t\tif left > 1000000 { // children first", "children before roots"),
    ("tiering/reads.go", "AND m.root_id = %s.%s::text AND u.route <> 'online' AND u.route_version <= %d)", "AND m.root_id = %s.%s::text AND u.route <> 'online' AND u.route_version <= %d + 1000000)", "only units off line at the snapshot are excluded (TR07)"),
    ("tiering/reads.go", "\"route_version <= $2 AND state IN ('published', 'released') ORDER BY id\"", "\"route_version <= $2 + 1000 AND state IN ('published', 'released') ORDER BY id\"", "cold units are the snapshot's"),
    ("tiering/reads.go", "\tif u.thawVersion != 0 {\n\t\troute, version = RoutePostgres, u.thawVersion\n\t}", "", "a thawed copy is read first (TR18)"),
    ("tiering/reads.go", "\t\tif !ok {\n\t\t\tcontinue\n\t\t}\n\t\treadable", "\t\t_ = ok\n\t\treadable", "an invisible aggregate is left out (TR12)"),
    ("tiering/reads.go", "\t\t\tif !readable[k] {\n\t\t\t\tdelete(a.Root, k)\n\t\t\t}", "\t\t\t_ = readable[k]", "fields are masked to the readable ones"),
    ("tiering/transfer.go", "AND NOT (r.version = ANY($2)) AND r.version >= 0 ", "AND NOT (r.version = ANY($2)) ", "a live thaw is not an orphan"),
]
