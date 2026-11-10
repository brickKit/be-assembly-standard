TITLE = "mdm/employee E3d: appointments"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
MUTANTS = [
    ("internal/appointments/appointments.go", "\tif overlap {\n", "\tif overlap && false {\n",
     "one person never holds one position twice at a time"),
    ("internal/appointments/appointments.go", "end(m, ctx, tx, actor, from, dayBefore(in.Date), \"transfer\")",
     "end(m, ctx, tx, actor, from, dayBefore(in.Date), \"ended\")", "a transfer ends the old appointment as a transfer"),
    ("internal/orgview/orgview.go", "`UPDATE appointment SET unit_path = $2 WHERE unit_id = $1 AND unit_path <> $2`",
     "`UPDATE appointment SET unit_path = unit_path WHERE unit_id = $1 AND unit_path <> $2`", "a unit's move rewrites the copied path"),
    ("internal/orgview/orgview.go", "if ok, err := get(ctx, tx, &v.positions, id, &p); err != nil || !ok || p.State != \"retired\" {",
     "if ok, err := get(ctx, tx, &v.positions, id, &p); err != nil || !ok || p.State != \"retired\" || true {",
     "a retired position ends the appointments on it"),
    ("employee/module.go", "\tb.Terminated = appointments.Ended(b)\n", "", "a termination ends every open appointment"),
    ("internal/appointments/appointments.go",
     "return sdkauthz.Facts{core.DimLegalEntity: sdkauthz.Value(legalEntity), core.DimDepartment: sdkauthz.Value(unitPath)}",
     "return sdkauthz.Facts{core.DimLegalEntity: sdkauthz.Value(legalEntity), core.DimDepartment: sdkauthz.Value(legalEntity + \"/\" + \"x\")}",
     "the department dimension is the appointment's unit path"),
]
