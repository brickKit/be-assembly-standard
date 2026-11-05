TITLE = "infra/iam-casdoor 3.0.26 in progress (item 4 T9c): a full recovery's 6.6 (sessions from before end) and no token while it runs"
BUILD = ["go", "vet", "-tags", "integration", "./iam"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
S, M, X = "iam/store.go", "iam/module.go", "iam/sessions.go"
MUTANTS = [
    (S, "\t\t\t\tAND recovery_generation >= (SELECT generation FROM be_recovery_generation)\n", "", "a session from before the recovery is used"),
    (S, "CASE WHEN recovery_generation < (SELECT generation FROM be_recovery_generation) THEN 'recovery'", "CASE WHEN false THEN 'recovery'", "its end is not named recovery"),
    (M, "\treturn m.endSessionsBeforeRecovery(ctx)\n}", "\treturn nil\n}", "the start does not end the sessions from before"),
    (S, "\t\tfor _, e := range all {\n\t\t\tif err := s.ended(ctx, tx, e.idHash); err != nil {", "\t\tfor _, e := range all {\n\t\t\tif err := error(nil); err != nil {", "the sweep's ends are not in the ended stream"),
    (M, "\t\terr := m.casdoor.endSessions(cctx, u)", "\t\terr := error(nil)\n\t\t_ = cctx", "Casdoor's sessions are left"),
    (X, "\tif s.m.rt.RecoveryPhase() != \"\" { // no token while a full recovery runs (be-protocol P1.23)", "\tif false { // no token while a full recovery runs (be-protocol P1.23)", "a token is issued while the recovery runs"),
]
