TITLE = "be-sdk-go tiering (T8, the two rewritten): route changes, old versions released, older structures"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'TestARouteChange|TestAnErasedVersions|TestAnOlderStructure' ./tiering/"]
MUTANTS = [
    ("tiering/reroute.go", "\t\t\tbacked = ok && finished.After(createdAt)", "\t\t\tbacked = ok && !finished.IsZero()", "old versions wait for a backup after the new one"),
    ("tiering/reroute.go", "\t\t\t\tif err := c.Store.Delete(ctx, obj.Key); err != nil {", "\t\t\t\tif err := error(nil); err != nil && obj.Key == \"\" {", "the old objects go"),
]
