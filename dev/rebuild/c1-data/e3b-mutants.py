TITLE = "mdm/employee E3b: the mdm/org projection"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
MUTANTS = [
    ("internal/orgview/orgview.go", "\t\tin.Kind, in.Data = projection.Partial, json.RawMessage(`{}`)\n", "\t\tin.Data = json.RawMessage(`{}`)\n",
     "an unknown action is partial: incomplete, then repaired"),
    ("internal/orgview/orgview.go", "func (v *View) all() []*kind { return []*kind{&v.legalEntities, &v.units, &v.positions} }",
     "func (v *View) all() []*kind { return []*kind{&v.legalEntities, &v.units} }", "the positions are projected and aligned"),
    ("internal/orgview/orgview.go", "\t_, err = m.RT.Work.Enqueue(ctx, tx, JobRepair, struct{}{})\n\treturn err\n}",
     "\treturn nil\n}", "a row waiting for a fetch queues the repair"),
]
