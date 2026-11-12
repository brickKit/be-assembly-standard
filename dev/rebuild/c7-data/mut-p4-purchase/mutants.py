TITLE = "erp/purchase 3.0.7: approvals on the flow kernel (C7 P4)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/orders/approval.go", "\tif p.NeedsApproval() {\n\t\tb, err := p.Approver()\n\t\tif err != nil {\n\t\t\treturn set, err\n\t\t}", "\tif false {\n\t\tb, err := p.Approver()\n\t\tif err != nil {\n\t\t\treturn set, err\n\t\t}", "PO03 a policy that wants an approval starts a task"),
    ("internal/policies/policies.go", "\tcase p.ApproverPrincipal != nil:\n\t\treturn flow.Binding{Principal: *p.ApproverPrincipal}, nil\n", "", "PO03 the principal approver"),
    ("internal/policies/policies.go", "\tcase in.ApproverPosition != nil && in.ApproverPrincipal != nil:\n\t\treturn core.Invalid(\"approver_principal\", \"an approver is a position or a principal, not both\")\n", "", "policy: a position or a principal, not both"),
    ("internal/orders/approval.go", "\t\tcommand, set = Reject, Set{Reason: i.Ending.Comment}", "\t\tcommand, set = Reject, Set{}", "PO05 the rejection's comment is the reason"),
    ("internal/orders/approval.go", "\tcommand, set := Approve, Set{ApprovedBy: i.Ending.By}", "\tcommand, set := Approve, Set{ApprovedBy: i.Initiator}", "PO04 the decider is the approver"),
    ("internal/acceptances/acceptances.go", "\t\tif err := orders.Released(m, ctx, tx, cur); err != nil {", "\t\tif err := error(nil); err != nil {", "PO08 the release check"),
    ("internal/receipts/receipts.go", "\t\tif err := orders.Released(m, ctx, tx, cur); err != nil {", "\t\tif err := error(nil); err != nil {", "PO07 the release check"),
    ("internal/requisitions/ordering.go", "\t\t\tif err := released(m, ctx, tx, r); err != nil {", "\t\t\tif err := error(nil); err != nil {", "PR06 the release check"),
    ("internal/orders/orders.go", "\t\t\t\tif err := end(ctx, tx, Document(o)); err != nil {", "\t\t\t\tif err := error(nil); err != nil {", "PO11 cancelling withdraws"),
    ("internal/orders/orders.go", "\t\tif err := m.Flow.SupersedeIn(ctx, tx, Document(o)); err != nil { // the approved revision's approval (PO06)", "\t\tif err := error(nil); err != nil {", "PO06 a revision supersedes"),
    ("internal/orders/approval.go", "\"quantity\": l.Quantity, \"unit\": l.Unit, \"unit_price\": l.UnitPrice}", "\"quantity\": l.Quantity, \"unit\": l.Unit}", "P17.7 the digest has the unit price"),
    ("internal/orders/approval.go", "OnReject: flow.Returned, RejectComment: true,", "OnReject: flow.Returned,", "PO05 a rejection says why"),
    ("internal/requisitions/approval.go", "\t\tcommand, set = Reject, Set{Reason: i.Ending.Comment}", "\t\tcommand, set = Reject, Set{}", "PR04 the rejection's comment is the reason"),
    ("internal/orders/approval.go", "\tif in.Version != nil && *in.Version != cur.Version {\n\t\treturn core.ErrVersion.New(fmt.Sprintf(\"the order is at version %d\", cur.Version))\n\t}\n\tchoice", "\tchoice", "PO04 the old route's version"),
]
