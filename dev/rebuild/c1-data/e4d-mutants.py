TITLE = "infra/authz 3.0.46 E4d: one natural person"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TestOnePerson", "./itest/"]
P = "internal/employment/person.go"
D = "internal/effectpoint/disposition.go"
MUTANTS = [
    (P, "ok && e == p.Employee || slices.Contains(p.Accounts, x) {", "ok && e == p.Employee || x == confirmer {",
     "the accounts linked to one employee are one person"),
    (P, "JOIN authz_employee_fact f2 ON f2.employee = f1.employee AND f2.kind = 'account_link' AND f2.state = 'active'",
     "JOIN authz_employee_fact f2 ON f2.employee = f1.employee AND f2.kind = 'account_link'",
     "an ended link no longer makes one person"),
    (P, "if e, ok := strings.CutPrefix(x, \"employee:\"); ok && e == p.Employee ||", "if e, ok := strings.CutPrefix(x, \"employee:\"); ok && e == \"-\" ||",
     "nobody confirms a link of their own employee"),
    ("internal/accounts/accountchange.go", "\tcase ok == core.Disproven:\n\t\treturn refused(\"the confirmer is the requester or the account itself (one person)\")",
     "\tcase ok == core.Disproven && false:\n\t\treturn refused(\"the confirmer is the requester or the account itself (one person)\")",
     "an account change's confirmer is another person"),
    ("internal/effectpoint/confirm.go", "\tif ind, err := Independent(m, ctx, tx, c.Confirmer, !lastApplied, requester, object); err != nil || ind != core.Proven {",
     "\tif ind, err := Independent(m, ctx, tx, c.Confirmer, !lastApplied, \"\", object); err != nil || ind != core.Proven {",
     "a record's confirmer is another person than the requester"),
    (D, "\tif in.accounts, err = PersonAccounts(m, ctx, tx, in.Subject); err != nil {",
     "\tif in.accounts, err = []string{in.Subject}, error(nil); err != nil {", "a disposition records the person's accounts"),
    (D, "\t\t\tnow, err := PersonAccounts(m, ctx, tx, a)", "\t\t\tnow, err := []string{a}, error(nil)",
     "an account linked after the disposition does not escape it"),
]
