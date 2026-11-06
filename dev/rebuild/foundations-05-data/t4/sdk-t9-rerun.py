TITLE = "be-sdk-go tiering (T9, the one rewritten): the recovery check be.tiering"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration -run 'TestTheTieringRecoveryCheck' ./tiering/"]
MUTANTS = [
    ("tiering/check.go", "\t\tif u := units[k[0]]; u != nil && u.versions[version] {", "\t\tif u := units[k[0]]; u != nil && version > -1000 {", "warm rows of no live version are a difference"),
]
