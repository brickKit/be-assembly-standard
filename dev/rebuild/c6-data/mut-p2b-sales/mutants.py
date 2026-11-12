# C6 P2b: erp/sales 3.0.50, crm/opportunity's quote requests (QR01-QR05). Each mutant must turn the integration tests red.
TITLE = "erp/sales 3.0.50: quote requests QR01-QR05"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
Q = "internal/quoterequests/quoterequests.go"
MUTANTS = [
    (Q, "core.ErrLegalEntity, core.ErrCurrency, core.ErrIneligible}", "core.ErrLegalEntity, core.ErrCurrency}",
     "QR04: an ineligible customer is an error (retried), not a refusal"),
    (Q, "r.Currency, r.OwnerID, r.OpportunityID, r.FactID, products,", "r.Currency, r.OwnerID, nil, r.FactID, products,",
     "QR03: the draft without the opportunity"),
    (Q, "r.Currency, r.OwnerID, r.OpportunityID, r.FactID, products,", "r.Currency, r.OwnerID, r.OpportunityID, r.FactID, []byte(\"[]\"),",
     "QR03: the requested products not kept"),
    (Q, "return core.Emit(m, ctx, tx, core.QuoteRequestRejected,", "return nil\n\t\treturn core.Emit(m, ctx, tx, core.QuoteRequestRejected,",
     "QR04: the refusal not published"),
    ("internal/quotations/quotations.go", 'if action == "send" && len(q.Lines) == 0 {', 'if false && len(q.Lines) == 0 {',
     "QR05: a draft without lines is sent"),
    ("internal/core/records.go", "(SELECT oq.opportunity_ref::text FROM quotation oq WHERE oq.id = o.quotation_id)", "NULL::text",
     "QR05: the order without the opportunity"),
]
