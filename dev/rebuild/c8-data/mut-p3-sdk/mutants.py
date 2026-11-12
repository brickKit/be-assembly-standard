TITLE = "be-sdk-go alpha.128: the notification intents (C8 P3)"
BUILD = ["go", "vet", "-tags", "integration", "./notify/", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./notify/", "./flow/"]
ENV = {"GOWORK": "/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/c8work/go.work"}
MUTANTS = [
    ("flow/intents.go", "\tif t.State != Pending || len(t.Candidates) == 0 {", "\tif t.State == Decided {", "P18.10 a task that is not pending withdraws"),
    ("flow/intents.go", "\t\tCollapseSeq: t.Version}", "\t\tCollapseSeq: 1}", "P18.10 the sequence is the task's version"),
    ("flow/intents.go", "\tif r := []rune(s); len(r) > 200 {\n\t\ts = string(r[:200])\n\t}", "\tif len(s) > 200 {\n\t\ts = s[:200]\n\t}", "P18.5 the title is cut by characters"),
    ("flow/instance.go", "\treturn k.intend(ctx, tx, t) // the notification intent goes with the projection (P18.10)", "\treturn nil", "P18.10 the intent goes with the projection"),
    ("notify/notify.go", "\tif !ExpiresInTime(in) {", "\tif false {", "P18.6 a deliver intent expires after it occurred"),
    ("notify/notify.go", "\t_, err := em.Emit(ctx, tx, Stream(in.Sender), events.Event{", "\t_, err := em.Emit(ctx, tx, in.Sender, events.Event{", "P18.2 the sender's own stream"),
    ("notify/notify.go", "\tif in.Kind != Deliver {\n\t\treturn true\n\t}", "\tif in.Kind == \"x\" {\n\t\treturn true\n\t}", "P18.6 a withdraw intent has no expiry"),
]
