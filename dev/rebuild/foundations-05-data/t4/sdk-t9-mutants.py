TITLE = "be-sdk-go tiering (T9): the recovery check be.tiering"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'TestTheTieringRecoveryCheck' ./tiering/"]
MUTANTS = [
    ("tiering/check.go", "\t\t\tif got := warm[[2]string{id, strconv.Itoa(u.manifest.Version)}]; got != want {", "\t\t\tif got := warm[[2]string{id, strconv.Itoa(u.manifest.Version)}]; got != want && false {", "a short warm copy is a difference (RC11)"),
    ("tiering/check.go", "\t\t\t\t\tif size, ok := objects[o.Key]; !ok || strconv.FormatInt(size, 10) != o.Bytes {", "\t\t\t\t\tif size, ok := objects[o.Key]; false && (!ok || strconv.FormatInt(size, 10) != o.Bytes) {", "a missing object is a difference (RC11)"),
    ("tiering/check.go", "\t\tif u.leftOnline > 0 {", "\t\tif false {", "a released unit with online rows is a difference"),
    ("tiering/check.go", "\t\t\tif u := units[parts[1]]; u != nil && u.live[parts[2]] {", "\t\t\tif u := units[parts[1]]; u != nil {", "an object of no live version is a difference (TR17)"),
    ("tiering/check.go", "\t\t\tif !strings.HasPrefix(o.Key, c.Store.Prefix+\"/exports/\") {", "\t\t\tif true {", "exports are not compared"),
    ("tiering/check.go", "\t\tif u := units[k[0]]; u != nil && u.versions[version] {", "\t\tif u := units[k[0]]; u != nil && version > -1000 {", "warm rows of no live version are a difference"),
    ("tiering/check.go", "\t\t\tif err := c.deleteOnline(ctx, u, cl, nil); err != nil {", "\t\t\tif err := error(nil); err != nil {", "the daily job continues a release"),
    ("tiering/check.go", "\tfor name := range c.Classes {\n\t\tfailed, err := c.CheckReadable(ctx, name)", "\tfor name := range map[string]bool{} {\n\t\tfailed, err := c.CheckReadable(ctx, name)", "an unreadable older structure is a difference (P15.34)"),
    ("tiering/check.go", "\t\tif u.route == RouteObject && c.Store == nil {", "\t\tif u.route == RouteObject && c.Store == nil && false {", "object units without a store are unprovable"),
]
