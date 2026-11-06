TITLE = "be-ops alpha.11, again the one that did not build: only the double failures after T"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
MUTANTS = [
    ("internal/recovery/verifyplan.go", "\t\tif err != nil || at.Before(t) {\n\t\t\tcontinue\n\t\t}\n\t\tout = append(out, EvidenceLoss{", "\t\tif err != nil || at.Before(t.Add(-24*time.Hour)) {\n\t\t\tcontinue\n\t\t}\n\t\tout = append(out, EvidenceLoss{", "only after T"),
]
