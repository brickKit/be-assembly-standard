"""P3b mutation check (bank accounts, receipts, fund facts): each mutation must turn the payment integration tests red.
Run from the payment component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

A = "internal/bankaccounts/accounts.go"
R = "internal/receipts/receipts.go"
M = [
 ("the number never masked", A, 'if !slices.Contains(readable, "number") {', 'if !slices.Contains(readable, "number") && false {'),
 ("a list row not masked", A, "return a.Mask(q.Fields(hits)), err", "return a, err"),
 ("an inactive account usable", A, 'if a.LegalEntityID != legalEntity || a.State != "active" {', "if a.LegalEntityID != legalEntity {"),
 ("another legal entity's account usable", A, 'if a.LegalEntityID != legalEntity || a.State != "active" {', 'if a.State != "active" {'),
 ("a number taken twice", A, "if tag.RowsAffected() == 0 {\n\t\t\treturn idem.Outcome{}, core.ErrCode", "if tag.RowsAffected() < 0 {\n\t\t\treturn idem.Outcome{}, core.ErrCode"),
 ("a bank reference taken twice", R, "if tag.RowsAffected() == 0 {\n\t\t\treturn idem.Outcome{}, core.ErrBankReference", "if tag.RowsAffected() < 0 {\n\t\t\treturn idem.Outcome{}, core.ErrBankReference"),
 ("another customer's order", R, "o.LegalEntityID != in.LegalEntityID || o.CustomerID != *in.PayerID", "o.LegalEntityID != in.LegalEntityID"),
 ("a suspended payer", R, "if in.PayerID != nil {\n\t\tif _, err := masterdata.PartnerOf", "if false {\n\t\tif _, err := masterdata.PartnerOf"),
 ("no rate snapshot", R, "ExchangeRate: ev.rate,", "ExchangeRate: nil,"),
 ("no fund fact on registration", R, "if err := f.Publish(m, ctx, tx); err != nil {\n\t\t\treturn idem.Outcome{}, err", "if err := error(nil); err != nil {\n\t\t\treturn idem.Outcome{}, err"),
 ("a reversal refers to nothing", R, 'f.FactID, f.Kind, f.ReversesFactID, f.RecordedAt = reversal, "reversal", &original, facts.Now()', 'f.FactID, f.Kind, f.ReversesFactID, f.RecordedAt = reversal, "reversal", func() *string { _ = original; return nil }(), facts.Now()'),
 ("a reversed receipt reversed again", "internal/receipts/lifecycle.go", 'Reversed: core.IgnoreCell("RC02"),', 'Reversed: {Rule: "RC02", Effect: core.Move, To: Reversed, Op: core.OpReceiptReverse},'),
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
