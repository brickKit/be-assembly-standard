TITLE = "mdm/employee E3f: the evidence, the replay, the record read, the recovery checks"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
MUTANTS = [
    ("internal/tightening/tightening.go", "Due: func(e core.Employee) bool { return e.State == \"active\" && date <= today },",
     "Due: func(e core.Employee) bool { return false },", "a termination writes its intent"),
    ("internal/appointments/appointments.go", "\tif last <= now { // ends now: a tightening\n\t\tev = intent(m, ctx, a, \"ended\", last)\n\t}",
     "\tif last <= now && false {\n\t\tev = intent(m, ctx, a, \"ended\", last)\n\t}", "the end of an appointment writes its intent"),
    ("internal/links/links.go", "\t\tif concluded, err = tightening.Conclude(ctx, tx, pending, t, link, out); err != nil {",
     "\t\tif concluded, err = false, error(nil); err != nil {", "the end of a link writes its conclusion"),
    ("internal/employees/employees.go", "\tif err := terminated(m, ctx, tx, actor, &next, date); err != nil {\n\t\treturn err\n\t}\n\tvar p core.Personal",
     "\treason := \"terminated\"\n\tnext.State, next.EndReason = \"terminated\", &reason\n\tvar p core.Personal", "the replay of a termination ends the appointments again"),
    ("internal/replay/replay.go", "\tcase rec.Object.Type == tightening.LinkType && kind == \"link_end\":", "\tcase rec.Object.Type == tightening.LinkType && kind == \"link_ended\":",
     "the replay knows the end of a link"),
    ("employee/checks.go", "\tc.Presence(core.Links, recovery.TablePresence(\"account_link\", \"id\", \"version\"))\n", "",
     "the recovery checks answer the links"),
    ("internal/source/source.go", "\t{\"account_link\", core.LinkCols,", "\t{\"account_link WHERE false AND\", core.LinkCols,",
     "the record read has the links"),
]
