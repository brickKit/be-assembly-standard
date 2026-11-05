TITLE = "be-ops alpha.10: a checked record (6.7, P12.20) is for review only when inconsistent"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
F = "internal/recovery/replay.go"
MUTANTS = [
    (F, '\t\tcase "consistent": // 6.7', '\t\tcase "consistent-no": // 6.7', "consistent needs no one"),
    (F, '\t\t\tif (outcome == OutcomeFailed || outcome == OutcomeUnimplemented) && r.Subject != "" {', '\t\t\tif (outcome == OutcomeFailed || outcome == OutcomeUnimplemented || outcome == "inconsistent") && r.Subject != "" {', "an inconsistent check closes nothing"),
    (F, '\t\tcase "consistent": // 6.7: the product outside the recovery group shows the change took place\n\t\tcase "applied", "reflected":', '\t\tcase "applied", "reflected", "consistent":', "an intent-only consistent one needs no one"),
]
