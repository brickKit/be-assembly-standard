TITLE = "be-sdk-go tiering (T8): route changes, old versions released, older structures"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'TestARouteChange|TestAnErasedVersions|TestAnOlderStructure' ./tiering/"]
MUTANTS = [
    ("tiering/reroute.go", "\t\t\tif cl, ok := c.Classes[class]; ok && len(cl.Routes) > 0 && cl.Routes[0] != route {", "\t\t\tif cl, ok := c.Classes[class]; ok && len(cl.Routes) > 0 && cl.Routes[0] != route && false {", "the transfer job moves units to the first route"),
    ("tiering/transfer.go", "\"route_version = CASE WHEN route = $2 THEN route_version ELSE $5 END WHERE id = $1\"", "\"route_version = CASE WHEN $5 > 0 THEN route_version ELSE $5 END WHERE id = $1\"", "the route version moves with the route"),
    ("tiering/reroute.go", "\t\tif createdAt.Add(c.Grace).After(now) {", "\t\tif false {", "old versions wait for the grace"),
    ("tiering/reroute.go", "\"SELECT count(*) FROM be_tier_lease WHERE catalog_version < $1 AND expires_at > now()\", rv)", "\"SELECT count(*) FROM be_tier_lease WHERE catalog_version < $1 AND expires_at > now() AND false\", rv)", "old versions wait for the older leases"),
    ("tiering/reroute.go", "\t\t\tbacked = ok && finished.After(createdAt)", "\t\t\tbacked = ok && !finished.IsZero()", "old versions wait for a backup after the new one"),
    ("tiering/reroute.go", "\"DELETE FROM be_tier_row WHERE unit::text = $1 AND version = $2\", unit, o.version)", "\"DELETE FROM be_tier_row WHERE unit::text = $1 AND version = $2 AND false\", unit, o.version)", "the old warm rows go"),
    ("tiering/reroute.go", "\t\t\t\tif err := c.Store.Delete(ctx, obj.Key); err != nil {", "\t\t\t\tif err := error(nil); err != nil && obj.Key == \"\" {", "the old objects go"),
    ("tiering/reroute.go", "\"UPDATE be_tier_manifest SET superseded_at = now() WHERE unit::text = $1 AND version = $2\"", "\"UPDATE be_tier_manifest SET superseded_at = NULL WHERE unit::text = $1 AND version = $2\"", "a released old version is recorded"),
    ("tiering/reroute.go", "\t\t\t\t\tif _, ok := conv[col]; !ok {", "\t\t\t\t\tif _, ok := conv[col]; !ok && false {", "a converted root keeps its locate columns"),
    ("tiering/reroute.go", "\t\t\tif _, err := FromCanonical(t, conv); err != nil {", "\t\t\tif _, err := FromCanonical(t, conv); err != nil && false {", "a converted row is the class's structure"),
    ("tiering/reads.go", "\tif m.SchemaVersion != cl.SchemaVersion { // an older structure", "\tif false { // an older structure", "an older structure goes through its converter (TR19)"),
    ("tiering/reads.go", "\t\t\tt := manifestTable(mt) // the structure the objects were written in", "\t\t\tt, _, _ := tableOf(cl, mt.Name)", "objects are decoded in their own structure"),
    ("tiering/reroute.go", "WHERE v <> $2 ORDER BY v, unit\"", "WHERE v = $2 ORDER BY v, unit\"", "the readability check reads the older structures"),
]
