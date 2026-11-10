TITLE = "erp/purchase 3.0.0 (C2 P3b): the purchase policy and requisitions (PR01-PR05)"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the routes answered CAPABILITY_UNSUPPORTED
R = "internal/requisitions/requisitions.go"
L = "internal/requisitions/lifecycle.go"
P = "internal/policies/policies.go"
MUTANTS = [
    (P, "updated_at = now() WHERE legal_entity_id = $1 AND version = $4`", "updated_at = now() WHERE legal_entity_id = $1 AND $4::bigint IS NOT NULL`",
     "a policy changes on its version"),
    (P, 'p := Policy{LegalEntityID: legalEntity, Approval: "required", OverReceiptPercent: "0"}',
     'p := Policy{LegalEntityID: legalEntity, Approval: "none", OverReceiptPercent: "0"}', "the starting policy needs approval"),
    (P, 'func (p Policy) NeedsApproval() bool { return p.Approval != "none" }', 'func (p Policy) NeedsApproval() bool { return true }',
     "PR02: a policy without approval approves at once"),
    (R, "				if r.SubmittedBy != nil && *r.SubmittedBy == actor {", "				if false && r.SubmittedBy != nil && *r.SubmittedBy == actor {",
     "PR03: not approved by its submitter"),
    (L, '			Submitted: refuse("PR01", notDraft),', '			Submitted: core.ProceedCell("PR01"),', "PR01: only a draft changes"),
    (R, '					return core.Invalid("reason", "a rejection has its reason")', '					_ = 0',
     "PR04: a rejection has its reason"),
    (R, "		if _, _, err := masterdata.Convert(m, ctx, l.ProductID, l.Quantity, l.Unit, p.products[l.ProductID].BaseUnit); err != nil {",
     "		if _, _, err := masterdata.Convert(m, ctx, l.ProductID, l.Quantity, l.Unit, l.Unit); err != nil {",
     "PR01: a unit converts to the base unit"),
    ("internal/orgunits/orgunits.go", "	if !ok || u.State != \"active\" || u.LegalEntityID != legalEntity {\n		return nil, nil, core.ErrDepartment.New(\"department \" + *id + \" is not an active department of the legal entity\")\n	}\n	return id, &u.Path, nil",
     "	if !ok || u.State != \"active\" {\n		return nil, nil, core.ErrDepartment.New(\"department \" + *id + \" is not an active department of the legal entity\")\n	}\n	return id, &u.Path, nil",
     "PR01: the department is of the legal entity"),
    (R, "		if in.Version != nil && *in.Version != r.Version {\n			return core.ErrVersion.New(fmt.Sprintf(\"the requisition is at version %d\", r.Version))\n		}\n		if err := writeLines(",
     "		if err := writeLines(", "PR01: a draft changes on its version"),
    (L, '			Approved:  core.IgnoreCell("PR03"),', '			Approved:  refuse("PR03", "x"),', "PR03: approving again answers it as it is"),
    (L, '			Rejected:  refuse("PR05", "a rejected requisition is not cancelled; it is already ended"),',
     '			Rejected:  core.MoveCell("PR05", Cancelled, core.OpReqEdit),', "PR05: a rejected requisition is not cancelled"),
    (L, '			Approved:  {Rule: "PR05", Effect: core.Move, To: Cancelled, Op: core.OpReqEdit, Guard: GuardNothingOrdered},',
     '			Approved:  refuse("PR05", "x"),', "PR05: an approved requisition nothing was ordered from is cancelled"),
    (R, "	if _, _, err := core.Check(c, core.OpReqRead, reqFacts(r)); err != nil {", "	if _, _, err := core.Check(c, core.OpReqRead, nil); err != nil {",
     "what one may not see does not exist"),
    (R, '	for _, p := range []string{"legal_entity_id", "department_id", "state"} {', '	for _, p := range []string{"legal_entity_id", "department_id"} {',
     "the list filters by state"),
]
