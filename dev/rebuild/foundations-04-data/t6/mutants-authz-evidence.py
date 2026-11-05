TITLE = "infra/authz 3.0.27 in progress (item 4 T6a, second round: the release, candidate and plan checks added; the replay mutant rewritten to build): the evidence the effect point writes, go test -tags integration ./authz/"
BUILD = ["go", "vet", "-tags", "integration", "./authz"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./authz/"]
C, P = "authz/change.go", "authz/planrun.go"
MUTANTS = [
    (C, "\tif req.Direction == Tighten && m.rt.Evidence != nil {", "\tif false && req.Direction == Tighten && m.rt.Evidence != nil {", "no intent before a tightening"),
    (C, "\t\t\tconcluded = true\n\t\t\treturn pending.Effective(ctx, tx)", "\t\t\tconcluded = true\n\t\t\treturn nil", "no effective conclusion"),
    (C, "\t\tif pending != nil && res.Outcome == \"applied\" && v.Row != 1 { // applied now, not a bound result again", "\t\tif pending != nil && res.Outcome == \"applied\" && v.Row != -1 { // applied now, not a bound result again", "a bound result again is concluded again"),
    (C, "\t\tif cerr := pending.Cancelled(ctx); cerr != nil {", "\t\tif cerr := error(nil); cerr != nil {", "no cancelled conclusion"),
    (C, "\tif res.Outcome == \"applied\" && (e.req.Direction == Widen || e.req.Direction == \"release\") && m.rt.Evidence != nil {", "\tif res.Outcome == \"applied\" && e.req.Direction == \"release\" && m.rt.Evidence != nil {", "a widening leaves no record"),
    (C, "\tif res.Outcome == \"applied\" && (e.req.Direction == Widen || e.req.Direction == \"release\") && m.rt.Evidence != nil {", "\tif res.Outcome == \"applied\" && e.req.Direction == Widen && m.rt.Evidence != nil {", "a release leaves no record"),
    (C, "\t\t\tc[\"candidate\"] = v", "\t\t\t_ = v", "the candidate is not in the evidence"),
    (P, "\tpeeked, pending, err := m.planIntent(ctx, a.Plan)", "\tpeeked, pending, err := \"\", (*evidence.Pending)(nil), error(nil)", "a plan's tightening item has no intent"),
]
