TITLE = "be-sdk-go alpha.85 in progress (item 4 T9c): the replay mutants again after ReplayTx and ParseReplayed were exported"
BUILD = ["go", "vet", "-tags", "integration", "./evidence/", "./launcher/", "./internal/host/"]
TEST = ["go", "test", "-count=1", "-p", "1", "-tags", "integration", "-run",
        "TestTheOwnerReplaysItsEvidence|TestTheReplayIsTheRecoveryToolsOnly|TestRecoveryPhases", "./evidence/", "./launcher/"]
R, B, M = "evidence/replay.go", "internal/host/build.go", "internal/host/member.go"
MUTANTS = [
    (R, "\tif err != nil || done {\n\t\treturn done, err\n\t}", "\tif err != nil {\n\t\treturn done, err\n\t}", "a reflected record is re-executed"),
    (R, "\t\t\toutcome, detail = Dangling, err.Error()\n\t\t\treturn errRollback", "\t\t\toutcome, detail = Dangling, err.Error()\n\t\t\treturn nil", "a dangling replay keeps what it wrote"),
    (R, "\tcase rec.Recorder.Component != component:", "\tcase false:", "another recorder's record is replayed"),
    (R, "\tcase rec.Phase != \"effective\" && rec.Phase != \"general\" && rec.Phase != \"intent\":", "\tcase false:", "a cancelled record is replayed"),
    (R, "\treturn false, reflect(ctx, tx, r.ID, r.Object)", "\treturn false, nil", "a replay leaves no change history"),
    (B, "\t\t\tCallers: []string{RecoveryTool}}})", "\t\t\tCallers: []string{grpcx.AnyComponent}}})", "any component may replay"),
    (B, "\t\tif m.Def.Replay == \"\" {", "\t\tif false {", "a replay without an operation starts"),
    (M, "\tmoving := phase == \"\" || phase == PhaseRedelivering || phase == PhaseReplaying // events and projections run", "\tmoving := phase == \"\" || phase == PhaseRedelivering // events and projections run", "replaying does not forward"),
]
