TITLE = "be-ops alpha.12: a deferred record is asked again after 6.4 (P12.22)"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
F = "internal/recovery/replay.go"
MUTANTS = [
    (F, "\t\tif outcome == OutcomeDeferred {\n\t\t\tlater = append(later, r)\n\t\t\tcontinue\n\t\t}\n", "", "a deferred one is held"),
    (F, "\tfor _, r := range later { // still deferred now", "\tfor _, r := range later[:0] { // still deferred now", "and asked again after the sources"),
]
