TITLE = "infra/iam-casdoor 3.0.23 in progress (item 4 T6b), round 2: the three mutants of round 1 that did not build, rewritten (a store without its evidence writer stands for the missing call)"
BUILD = ["go", "vet", "-tags", "integration", "./iam"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
S, R = "iam/sessions.go", "iam/reconcile.go"
MUTANTS = [
    (S, "\tp := m.store.intent(c.Ctx(), \"credential_tightening\",", "\tp := store{}.intent(c.Ctx(), \"credential_tightening\",", "a password change has no intent"),
    (R, "\t\t\tif err := s.general(ctx, tx, \"account_status\",", "\t\t\tif err := (store{}).general(ctx, tx, \"account_status\",", "a rollback leaves no record"),
    (R, "\t\treturn s.general(ctx, tx, \"credential_tightening_in_product\",", "\t\treturn (store{}).general(ctx, tx, \"credential_tightening_in_product\",", "a credential change in Casdoor leaves no record"),
]
