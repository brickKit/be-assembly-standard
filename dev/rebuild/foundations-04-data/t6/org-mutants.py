TITLE = "mdm/org 3.0.16 in progress (item 4 T6c): the evidence of the organization's tightenings, go test -tags integration ./org/"
BUILD = ["go", "vet", "-tags", "integration", "./org"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./org/"]
U, M, E = "org/units.go", "org/module.go", "org/evidence.go"
MUTANTS = [
    (U, "\t\t\tp = intent(ctx, m.ev, tight, id, pre.Version, pre)", "\t\t\tp = intent(ctx, nil, tight, id, pre.Version, pre)", "a unit's tightening has no intent"),
    (M, "\t\t\tp = intent(ctx, m.ev, tight, id, pre.Version, pre)", "\t\t\tp = intent(ctx, nil, tight, id, pre.Version, pre)", "a legal entity's tightening has no intent"),
    (U, "\t\tif concluded, err = conclude(ctx, tx, p, tight, cur, next); err != nil {", "\t\tif concluded, err = conclude(ctx, tx, (*evidence.Pending)(nil), tight, cur, next); err != nil {", "a unit's tightening is not concluded"),
    (M, "\t\tif concluded, err = conclude(ctx, tx, p, tight, cur, next); err != nil {", "\t\tif concluded, err = conclude(ctx, tx, (*evidence.Pending)(nil), tight, cur, next); err != nil {", "a legal entity's tightening is not concluded"),
    (E, "\tif p != nil && !concluded {", "\tif p != nil && !concluded && false {", "an intent that did not tighten is never cancelled"),
    (E, "\t\t\treturn slices.ContainsFunc(above(b.Path),", "\t\t\treturn true || slices.ContainsFunc(above(b.Path),", "a move that only adds units above is concluded as a tightening"),
    (E, "\t\t\treturn slices.ContainsFunc(above(b.Path),", "\t\t\treturn false && slices.ContainsFunc(above(b.Path),", "a move out from under a unit is not concluded"),
    (E, "\tdue:      func(u Unit) bool { return u.State == \"active\" },", "\tdue:      func(u Unit) bool { return false },", "a retirement has no intent"),
    (E, "\t\tdue:      func(e LegalEntity) bool { return state != \"active\" && e.State != \"retired\" },", "\t\tdue:      func(e LegalEntity) bool { return e.State != \"retired\" },", "a legal entity made active again writes an intent"),
]
