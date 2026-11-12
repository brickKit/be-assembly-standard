TITLE = "erp/payment 3.0.11: approvals on the flow kernel (C7 P4)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/policies/policies.go", "\tcase p.ApproverPrincipal != nil:\n\t\treturn flow.Binding{Principal: *p.ApproverPrincipal}, nil\n", "", "PR03 the principal approver"),
    ("internal/requests/actions.go", "\t\treturn startApproval(m, ctx, tx, r, approver, actor)", "\t\treturn func() error { _ = approver; return nil }()", "PR03 submitting starts the approval"),
    ("internal/requests/approval.go", "\t\tif claims := r.claims(); len(claims) > 0 {", "\t\tif claims := r.claims(); len(claims) > 1000 {", "PR03 a rejection's claims released"),
    ("internal/requests/approval.go", "updated_at = now() WHERE id = $1`, r.ID, Approved, i.Ending.By); err != nil {", "updated_at = now() WHERE id = $1`, r.ID, Approved, i.Initiator); err != nil {", "PR03 the decider is the approver"),
    ("internal/requests/approval.go", "updated_at = now() WHERE id = $1`, r.ID, Draft, i.Ending.Comment); err != nil {", "updated_at = now() WHERE id = $1`, r.ID, Draft, nil); err != nil {", "PR03 the rejection's comment is the reason"),
    ("internal/requests/approval.go", "\terr = m.Flow.ReleaseIn(ctx, tx, Document(r), keyRevision, []string{digest})", "\terr = func() error { _ = digest; return nil }()", "PR04, PR05 the release check"),
    ("internal/requests/actions.go", "\t\tif err := released(m, ctx, tx, r); err != nil { // the approval still covers what is paid (P17.7)", "\t\tif err := error(nil); err != nil {", "PR05 the release check at the execution"),
    ("internal/requests/approval.go", "\tif me == applicant || actor == *r.ApplicantID {", "\tif false {", "PR04 the releaser is not the applicant"),
    ("internal/requests/approval.go", "\tcase Submitted:\n\t\treturn m.Flow.WithdrawIn(ctx, tx, Document(r))\n", "", "PR07 cancelling withdraws"),
    ("internal/requests/approval.go", "\tcase Approved, Ready:\n\t\treturn m.Flow.SupersedeIn(ctx, tx, Document(r))\n", "", "PR03 rejecting an approved request supersedes"),
    ("internal/entries/approval.go", "\tif err := apply(m, ctx, tx, e, command, i.Ending.By, in, rate); err != nil {", "\tif err := apply(m, ctx, tx, e, command, i.Initiator, in, rate); err != nil {", "BE02 posted by its decider"),
    ("internal/entries/approval.go", "\tif _, err := tx.Exec(ctx, `UPDATE bank_entry SET rate = $2 WHERE id = $1`, e.ID, rate); err != nil {", "\tif _, err := tx.Exec(ctx, `UPDATE bank_entry SET rate = $2 WHERE id = $1`, e.ID, (*masterdata.Rate)(nil)); err != nil {", "BE02 the rate taken at the submission"),
    ("internal/entries/actions.go", "\t\t\t\tif err := m.Flow.WithdrawIn(ctx, tx, Document(e)); err != nil {", "\t\t\t\tif err := error(nil); err != nil {", "BE04 cancelling a submitted entry withdraws"),
    ("internal/requests/approval.go", "OnReject: flow.Returned, RejectComment: true,\n\t\tManual: true,", "OnReject: flow.Returned,\n\t\tManual: true,", "PR03 a rejection says why"),
    ("internal/requests/approval.go", "\"currency\": r.Currency, \"amount\": r.Amount, \"lines\": lines})", "\"currency\": r.Currency, \"lines\": lines})", "P17.7 the digest has the amount"),
]
