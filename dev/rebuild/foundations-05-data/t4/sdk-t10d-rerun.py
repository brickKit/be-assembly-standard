TITLE = "be-sdk-go tiering (T10d, NFC again with its test): a leaf's composite key, the columns check, text arrays"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -run 'TestAClassDeclaration|Vectors|RoundTrip|WrittenAgain|TestATextArrayIsNFC' ./tiering/ && go test -count=1 -tags integration -run 'TestAClassMustDeclareItsTables|TestAnAggregateOfThreeLevels' ./tiering/"]
MUTANTS = [
    ("tiering/rows.go", "\t\tout[i] = canon.Text(s)", "\t\tout[i] = s", "each element is NFC"),
]
