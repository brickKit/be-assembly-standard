TITLE = "erp/payment 3.0.11: mutant 8 rewritten so it builds, and the survivors of the first round"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/requests/approval.go", "\tif me == applicant || actor == *r.ApplicantID {", "\tif (me == applicant || actor == *r.ApplicantID) && false {", "PR04 the releaser is not the applicant"),
    ("internal/entries/actions.go", "\t\t\t\tif err := m.Flow.WithdrawIn(ctx, tx, Document(e)); err != nil {", "\t\t\t\tif err := error(nil); err != nil {", "BE04 cancelling a submitted entry withdraws"),
]
