# C6 P2b rerun: the two mutants of mutants.py that did not build, written so they build.
TITLE = "erp/sales 3.0.50: quote requests, the two mutants rewritten"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
Q = "internal/quoterequests/quoterequests.go"
MUTANTS = [
    (Q, "products, err := json.Marshal(r.Lines)", "products, err := json.Marshal([]int{})",
     "QR03: the requested products not kept"),
    (Q, "return core.Emit(m, ctx, tx, core.QuoteRequestRejected, r.FactID,", "return core.Emit(m, ctx, tx, core.QuotationChanged, r.FactID,",
     "QR04: the refusal not published (another type instead)"),
]
