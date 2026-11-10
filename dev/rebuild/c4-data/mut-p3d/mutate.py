"""P3d mutation check: each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

S = "internal/supplierinvoices/"
M = [
 ("no quantity tolerance", S+"matching.go", "limit := core.Times(invoiceable, core.Sum(\"1\", core.Per(tol.QuantityPercent, \"100\", 12)), core.PriceScale)", "limit := invoiceable"),
 ("no price check", S+"matching.go", "if core.Cmp(gap, core.Times(b.GetUnitPrice(), core.Per(tol.PricePercent, \"100\", 12), core.PriceScale)) > 0 {", "if false && core.Cmp(gap, \"0\") > 0 {"),
 ("invoiced not subtracted", S+"matching.go", "invoiceable := core.Minus(done, orZero(invoiced[*l.OrderLineID]))", "invoiceable := core.Minus(done, \"0\")"),
 ("goods not converted to the order unit", S+"matching.go", "done = toOrderUnit(b, b.GetReceivedBaseQuantity())", "done = b.GetReceivedBaseQuantity()"),
 ("no rematch before posting", S+"posting.go", "if v.State == Matched {\n\t\tinvoiced, err", "if false {\n\t\tinvoiced, err"),
 ("maker approves", S+"actions.go", "if v.MakerID == actor {", "if false {"),
 ("expense posts unapproved", S+"actions.go", "if v.DifferenceApprovedBy == nil {\n\t\t\treturn core.ErrState.New(\"an expense invoice posts once approved\")", "if false {\n\t\t\treturn core.ErrState.New(\"an expense invoice posts once approved\")"),
 ("movements ignore what is invoiced", S+"posting.go", "avail := core.Minus(core.Minus(mv.GetReceivedBaseQuantity(), mv.GetReturnedBaseQuantity()), taken)", "avail := core.Minus(core.Minus(mv.GetReceivedBaseQuantity(), mv.GetReturnedBaseQuantity()), \"0\")"),
 ("price not per base unit", S+"posting.go", "\"unit_price\": core.Per(core.Times(l.UnitPrice, b.GetOrderedQuantity(), 12), b.GetOrderedBaseQuantity(), core.PriceScale),", "\"unit_price\": l.UnitPrice,"),
 ("expense lines not booked", S+"posting.go", "lines = append(lines, expenses...)", "lines = append(lines, expenses[:0]...)"),
 ("approval survives a change", S+"invoices.go", "state = 'draft', difference_approved_by = NULL, difference_reason = NULL,", "state = 'draft',"),
 ("foreign currency taken", S+"invoices.go", "if in.Currency != p.le.BaseCurrency {", "if false {"),
 ("cancelled number still taken", "finance/migrations/0001_finance.up.sql", "CREATE UNIQUE INDEX supplier_invoice_supplier_number ON supplier_invoice (legal_entity_id, supplier_id, supplier_number)\n    WHERE state <> 'cancelled';", "CREATE UNIQUE INDEX supplier_invoice_supplier_number ON supplier_invoice (legal_entity_id, supplier_id, supplier_number);"),
 ("no payable", S+"posting.go", "Kind: \"payable\",", "Kind: \"receivable\","),
]
survived = []
for mut in M:
    name, edits = mut[0], (mut[1] if isinstance(mut[1], list) else [mut[1:]])
    saved = {}
    for path, old, new in edits:
        p = pathlib.Path(path)
        saved.setdefault(p, p.read_text())
        src = p.read_text()
        assert src.count(old) == 1, (name, old, src.count(old))
        p.write_text(src.replace(old, new))
    try:
        r = subprocess.run(["go", "test", "-count=1", "-tags", "integration", "./itest/"], capture_output=True, text=True, timeout=240)
        out = r.stdout + r.stderr
        if "build failed" in out or "[setup failed]" in out:
            print(f"BUILD-FAILED {name}"); survived.append(name)
        elif r.returncode == 0:
            print(f"SURVIVED {name}"); survived.append(name)
        else:
            line = next((l.strip() for l in out.splitlines() if "_test.go:" in l and "Error Trace" not in l), "")
            print(f"killed {name}  ({line[:110]})")
    finally:
        for p, src in saved.items():
            p.write_text(src)
    sys.stdout.flush()
print("MUTATION-DONE", len(M) - len(survived), "of", len(M), "killed")
sys.exit(1 if survived else 0)
