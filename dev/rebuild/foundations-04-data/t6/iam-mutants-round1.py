TITLE = "infra/iam-casdoor 3.0.23 in progress (item 4 T6b): the evidence the identity member writes, go test -tags integration ./iam/"
BUILD = ["go", "vet", "-tags", "integration", "./iam"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
S, A, R, ST = "iam/sessions.go", "iam/accountops.go", "iam/reconcile.go", "iam/store.go"
MUTANTS = [
    (S, "\tp := m.store.intent(c.Ctx(), \"credential_tightening\", a.principal, a.securityVersion,", "\tp := (*evidence.Pending)(nil); _ = m.store.intent\n\t_ = fmt.Sprint(c.Ctx(), \"credential_tightening\", a.principal, a.securityVersion,", "a password change has no intent"),
    (ST, "\t\treturn run(ctx, tx, after) // the evidence's conclusion, in the same transaction", "\t\treturn nil", "a security change concludes no evidence"),
    (S, "\tdefer func() { settle(c.Ctx(), p, done) }()", "\t_ = done", "a refused password change leaves its intent open"),
    (A, "\t\tp = m.store.intent(ctx, \"account_status\", a.principal, a.securityVersion, change)", "\t\tp = nil", "a disablement has no intent"),
    (A, "\t\treturn m.store.general(ctx, tx, \"account_reenable\", a.principal, a.securityVersion, change)", "\t\treturn nil", "a re-enable leaves no record"),
    (A, "\tif a.securityVersion, err = m.store.securityChange(ctx, a.principal, \"forced\", \"\", effective(p)); err != nil {", "\tif a.securityVersion, err = m.store.securityChange(ctx, a.principal, \"forced\", \"\", nil); err != nil {", "a forced logout concludes nothing"),
    (A, "\tif a.securityVersion, err = m.store.resetFactors(ctx, a.principal, u.secondFactors(), effective(p)); err != nil {", "\tif a.securityVersion, err = m.store.resetFactors(ctx, a.principal, u.secondFactors(), nil); err != nil {", "a reset concludes nothing"),
    (R, "\tif s.ev == nil || !u.off() {\n\t\treturn nil, nil\n\t}", "\tif true {\n\t\treturn nil, nil\n\t}", "a console disablement has no intent"),
    (R, "\t\t\tif err := s.general(ctx, tx, \"account_status\", principal, 0, map[string]any{\"status\": status, \"source\": \"rollback\",", "\t\t\tif err := error(nil); err != nil && s.ev != nil && fmt.Sprint(map[string]any{\"status\": status, \"source\": \"rollback\",", "a rollback leaves no record"),
    (R, "\t\treturn s.general(ctx, tx, \"credential_tightening_in_product\", principal, version-1, map[string]any{\"kind\": reason,", "\t\treturn nil; _ = s.general; _ = fmt.Sprint(ctx, tx, \"credential_tightening_in_product\", principal, version-1, map[string]any{\"kind\": reason,", "a credential change in Casdoor leaves no record"),
]
