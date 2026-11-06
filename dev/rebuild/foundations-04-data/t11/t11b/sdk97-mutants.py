TITLE = "be-sdk-go alpha.97: the evidence transfer in the recovery phases but frozen (P1.23)"
BUILD = ["go", "vet", "-tags", "integration", "./launcher/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TheEvidenceTransferRunsInTheRecoveryPhases", "./launcher/"]
F = "internal/host/build.go"
MUTANTS = [
    (F, "\tif w.Store != nil {\n\t\tm.loops = append(m.loops, loop{name: \"the evidence transfer\"", "\tif w.Store != nil && false {\n\t\tm.loops = append(m.loops, loop{name: \"the evidence transfer\"", "the evidence transfer runs in the recovery phases"),
    (F, "\t\t\tin: func(phase string) bool { return phase != \"\" && phase != PhaseFrozen },\n\t\t\trun: func(ctx context.Context) error {\n\t\t\t\tctx, cancel", "\t\t\tin: func(phase string) bool { return phase != \"\" },\n\t\t\trun: func(ctx context.Context) error {\n\t\t\t\tctx, cancel", "not in frozen"),
]
