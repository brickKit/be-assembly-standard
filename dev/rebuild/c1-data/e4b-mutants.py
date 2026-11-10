TITLE = "infra/authz 3.0.46 E4b: the employee source"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TestTheEmployeeSource", "./itest/"]
MUTANTS = [
    ("authz/module.go", "\tif emp == \"\" {\n\t\treturn nil\n\t}", "\tif emp == \"\" || true {\n\t\treturn nil\n\t}",
     "the employee source is built when the deployment names one"),
    ("internal/employment/facts.go", "\tcase r.PositionID != \"\":\n\t\tf.Kind = KindAppointment",
     "\tcase r.PositionID != \"\":\n\t\tf.Kind = KindEmployee", "an appointment's fact is an appointment"),
    ("internal/employment/facts.go", "ON CONFLICT (record) DO UPDATE SET employee = excluded.employee, account = excluded.account,\n\t\t\t\tstate = excluded.state, version = excluded.version)",
     "ON CONFLICT (record) DO NOTHING)", "a change replaces the fact"),
    ("internal/restore/recoverystep.go", "\tif m.Employees != nil {\n\t\tsources = append(sources, m.Employees)\n\t}",
     "", "6.4 waits for the employee source too"),
]
