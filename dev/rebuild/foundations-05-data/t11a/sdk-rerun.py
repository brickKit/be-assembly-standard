TITLE = "be-sdk-go alpha.116 (T11a): the first mutant again, rewritten so that it builds"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/", "./internal/host/", "./launcher/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1 && go test -count=1 -tags integration "
        "-run 'TestTheDailyCleanupRemovesEveryUnitsOrphans|TestAnErasureVoidsTheExports|TestOnlyTheCurrentClaimPublishes|"
        "TestAThawedUnitReadsFromItsCopy' ./tiering/ && go test -count=1 -tags integration -run TestAComponentWithClassesServes ./launcher/"]
MUTANTS = [
    ("tiering/transfer.go", "\t\t\tif slices.ContainsFunc(named[u], func(p string) bool { return strings.HasPrefix(rest, p) }) ||",
     "\t\t\tif slices.ContainsFunc(named[u+\"-\"], func(p string) bool { return strings.HasPrefix(rest, p) }) ||",
     "an object a manifest names is never an orphan"),
]
