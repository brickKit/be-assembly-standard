TITLE = "infra/authz 3.0.46 E4c: account links' confirmations"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "-run", "TestAccountLinks", "./itest/"]
F = "internal/accounts/links.go"
MUTANTS = [
    (F, "return authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_CONFIRMATION_REQUIRED, \"protected: an account's link to an employee\", nil",
     "return authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_ALLOWED, \"\", nil", "a link always needs a confirmation"),
    (F, "AND link_action = $4 AND employee_version = $5`,", "AND link_action = $4 AND (employee_version = $5 OR $5 > 0)`,",
     "the confirmation binds the employee's version"),
    (F, "\tcase c.confirmer == in.GetRequester() || c.confirmer == in.GetAccount():", "\tcase c.confirmer == in.GetAccount():",
     "the confirmer is not the requester"),
    (F, "\t\tcase others:\n\t\t\treturn refused(\"another authorization admin is available: the owner does not stand in for a link\")\n",
     "\t\tcase others && false:\n\t\t\treturn refused(\"another authorization admin is available: the owner does not stand in for a link\")\n",
     "the owner stands in on a link only when no other admin is available"),
    (F, "\tif confirmer == in.Account {\n\t\treturn \"\", time.Time{}, errs.New(errs.ReasonPermissionDenied, \"nobody confirms a link of their own account\")",
     "\tif false && confirmer == in.Account {\n\t\treturn \"\", time.Time{}, errs.New(errs.ReasonPermissionDenied, \"nobody confirms a link of their own account\")",
     "nobody confirms a link of their own account"),
    (F, "\t\tif err := use(actionLink, f.Confirmation); err != nil {", "\t\tif err := error(nil); err != nil {",
     "the link applied uses its confirmation"),
    (F, "\t\treturn use(actionUnlink, f.EndConfirmation)", "\t\treturn use(actionLink, f.EndConfirmation)",
     "the end applied uses its end confirmation"),
    (F, "\tif len(in.GetAccounts()) > MaxAdministratorsAsked {", "\tif len(in.GetAccounts()) > 10*MaxAdministratorsAsked {",
     "Administrators asks at most 100"),
    ("authz/services.go", "\t\t\"Administrators\":     {Operation: core.OpAccountCheck, Callers: employee}})",
     "\t\t\"Administrators\":     {Operation: core.OpAccountCheck, Callers: []string{grpcx.AnyComponent}}})",
     "Administrators answers the employee member only"),
]
