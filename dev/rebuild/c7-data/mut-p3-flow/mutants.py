# C7 P3: be-sdk-go's flow kernel. Each mutant must turn the flow package's integration tests red.
TITLE = "be-sdk-go flow kernel (P17.4-P17.18)"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
I, D, R = "flow/instance.go", "flow/decisions.go", "flow/routes.go"
MUTANTS = [
    (I, "			if p == i.InitiatorPerson {\n				continue\n			}", "			_ = p", "P17.8: the initiator's person is not left out"),
    (D, "		s.Self = person == i.InitiatorPerson || person == initiatorNow", "		s.Self = false", "P17.12: self-approval by person not checked"),
    (D, "		case !holds:\n			s.Qualification = NotQualified", "		case !holds:", "P17.10: one who left the position still decides"),
    (D, "RevisionMatches: i.KeyRevision == revision,", "RevisionMatches: true,", "P17.10: a changed revision is not refused"),
    (I, "	if hook {\n		return k.Ended(ctx, tx, i)\n	}", "	_ = hook", "P17.6: the end hook is not called"),
    (I, "		if digests[n] != i.Digests[n] {", "		if false && digests[n] != i.Digests[n] {", "P17.7: a changed approval basis releases"),
    (R, "			case reason == \"\":\n				return k.bump(ctx, tx, id, Pending, \"\", cands)", "			case reason == \"\":\n				return nil", "P17.8: a resolved paused task stays paused"),
    (I, "	for _, id := range open {\n		if err := k.bump(ctx, tx, id, Superseded, \"\", nil); err != nil {", "	for _, id := range open[:0] {\n		if err := k.bump(ctx, tx, id, Superseded, \"\", nil); err != nil {", "P17.6: an ended instance's open tasks stay open"),
    (D, "		return Task{}, refused{reason: o.Refused, err: refusal(o.Refused)}", "		return Task{}, refusal(o.Refused)", "P17.10: a refused check has no security record"),
]
