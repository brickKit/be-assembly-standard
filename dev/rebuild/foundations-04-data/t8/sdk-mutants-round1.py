TITLE = "be-sdk-go alpha.81 in progress (item 4 T8b): recovery mode (P1.22-P1.24), the launcher and shell tests that cover it"
BUILD = ["go", "vet", "-tags", "integration", "./launcher/", "./shell/", "./internal/host/", "./httpx/"]
TEST = ["go", "test", "-count=1", "-p", "1", "-tags", "integration", "-run", "TestRecoveryPhases|TestAShellInRecovery",
        "./launcher/", "./shell/"]
M, E, S = "internal/host/member.go", "httpx/engine.go", "shell/shell.go"
MUTANTS = [
    (M, "\tif phase := m.Phase(); phase != \"\" {\n\t\tm.SetState(RecoveryReady)", "\tif phase := m.Phase(); phase == \"x\" {\n\t\tm.SetState(RecoveryReady)", "a member in a phase is plainly ready"),
    (M, "func (m *Member) IsReady() bool { s := m.State(); return s == Ready || s == RecoveryReady }", "func (m *Member) IsReady() bool { s := m.State(); return s == Ready }", "recovery_ready is not routable"),
    (M, "\t\tout[\"recovery_phase\"] = phase\n\t}\n\treturn out\n}\n\n// Start", "\t\t_ = phase\n\t}\n\treturn out\n}\n\n// Start", "the self-description has no phase"),
    (E, "\t\tif d.Phase != \"\" { // a full recovery: nothing on the user surface (P1.23)", "\t\tif false {", "the user surface serves during a recovery"),
    (E, "\t\t\t\tif phase := d.Platform.Phase(); phase != \"\" { // ready in recovery mode: routable (P1.22)", "\t\t\t\tif phase := d.Platform.Phase(); phase == \"x\" {", "readiness does not say the phase"),
    (M, "\tmoving := phase == \"\" || phase == PhaseRedelivering // events and projections run", "\tmoving := true", "frozen forwards and receives"),
    (M, "\tif m.hasJobs && phase == \"\" {", "\tif m.hasJobs {", "jobs run during a recovery"),
    (M, "\t\tif !moving {\n\t\t\tbreak\n\t\t}\n", "", "subscriptions start while frozen"),
    (M, "\tif m.forwarder != nil && moving {", "\tif m.forwarder != nil && phase == \"\" {", "redelivering does not forward"),
    (S, "\treturn members[0].Phase()", "\treturn \"\"", "a shell does not say its members' phase"),
]
