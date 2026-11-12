TITLE = "be-sdk-go alpha.123 flow: rejection comments, automatic approvals, the ending decision, decisions by the document"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
MUTANTS = [
    ("flow/decisions.go", "if in.Decision == Reject && d.RejectComment &&", "if false && in.Decision == Reject && d.RejectComment &&", "P17.1 a rejection without a comment"),
    ("flow/decisions.go", "i.Ending = &DecisionRecord{Decision: in.Decision, By: me, At: canon.Time(at), Comment: in.Comment}", "i.Ending = &DecisionRecord{Decision: in.Decision, By: i.Initiator, At: canon.Time(at)}", "P17.6 the end hook gets the decision"),
    ("flow/decisions.go", "\t\t\t\tWHEN d.by_account = $3 THEN 1\n", "\t\t\t\tWHEN d.by_account = $3 THEN 9\n", "P17.14 a repeat replays the caller's decided task"),
    ("flow/decisions.go", "key = \"flow:\" + task + \":\" + string(c)", "key = \"flow:\" + task", "P17.14 the default key"),
    ("flow/decisions.go", "\t\treturn Task{}, refusal(ReasonTaskNotPending)\n\t}\n\tif err != nil {", "\t\treturn Task{}, errNotFound()\n\t}\n\tif err != nil {", "P17.14 no instance answers TASK_NOT_PENDING"),
    ("flow/instance.go", "\tcase s.Automatic && d.Manual:", "\tcase false && s.Automatic && d.Manual:", "P17.5 people must approve"),
    ("flow/instance.go", "\tif s.Automatic {\n\t\tstate = Approved\n\t}", "\tif false {\n\t\tstate = Approved\n\t}", "P17.5 automatic is approved at once"),
    ("flow/kernel.go", "\tif k.Directory == nil {\n\t\treturn account, nil\n\t}\n\treturn k.Directory.PersonOf(ctx, tx, account)", "\treturn account, nil", "P17.12 the person behind an account"),
]
