TITLE = "mdm/employee 3.0.3 (C1 E6, after the consistency exam): later terminations and last days recorded and replayed"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the fixes (each test written first): the transfer's check of the old appointment's department, the
# refused withdrawal on the date, the record of a later termination
MUTANTS = [
    ("internal/replay/replay.go", 'kind == "termination_scheduled":', 'kind == "termination_scheduled_x":',
     "a later termination is registered again by the replay"),
    ("internal/appointments/appointments.go", "	if err != nil || a.State == \"ended\" || a.EndDate != nil && *a.EndDate <= last {\n		return err\n	}\n	if _, err := tx.Exec(ctx, `UPDATE appointment SET end_date = $2",
     "	if err != nil || a.State == \"ended\" || true {\n		return err\n	}\n	if _, err := tx.Exec(ctx, `UPDATE appointment SET end_date = $2",
     "a later last day is set again by the replay"),
    ("internal/tightening/tightening.go", "		Due: func(a core.Appointment) bool { return a.State != \"ended\" && (a.EndDate == nil || *a.EndDate > last) },",
     "		Due: func(a core.Appointment) bool { return false },", "a later last day is recorded when set"),
]
