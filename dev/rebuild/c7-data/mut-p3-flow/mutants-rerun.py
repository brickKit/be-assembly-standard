# C7 P3 rerun: the three mutants of mutants.py that did not build, written so they build.
TITLE = "be-sdk-go flow kernel: the three mutants rewritten"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
D, R = "flow/decisions.go", "flow/routes.go"
MUTANTS = [
    (D, "		s.Self = person == i.InitiatorPerson || person == initiatorNow", "		s.Self = (person == i.InitiatorPerson || person == initiatorNow) && false",
     "P17.12: self-approval by person not checked"),
    (D, "RevisionMatches: i.KeyRevision == revision,", "RevisionMatches: i.KeyRevision == revision || true,", "P17.10: a changed revision is not refused"),
    (R, "				return k.bump(ctx, tx, id, Pending, \"\", cands)", "				return k.bump(ctx, tx, id, Paused, ReasonNoAssignee, cands[:0])",
     "P17.8: a resolved paused task stays paused"),
]
