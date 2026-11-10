"""P3c mutation check: each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

M = [
 ("every dedup layer removed", [
    ("internal/intake/receive.go", "\t\treturn nil\n\t}\n\tif err != nil {\n\t\treturn err\n\t}\n\t_, err = m.RT.Work.Enqueue", "\t}\n\tif err != nil \u0026\u0026 !errors.Is(err, pgx.ErrNoRows) {\n\t\treturn err\n\t}\n\t_, err = m.RT.Work.Enqueue"),
    ("internal/intake/receive.go", "return state == \"pending\", nil", "return true, nil"),
    ("internal/intake/receive.go", "if err != nil || f.State == \"posted\" {", "if err != nil {"),
    ("finance/migrations/0001_finance.up.sql", "CREATE UNIQUE INDEX voucher_source", "CREATE INDEX voucher_source"),
    ("finance/migrations/0001_finance.up.sql", "CREATE UNIQUE INDEX open_item_source", "CREATE INDEX open_item_source")]),
 ("no rounding adjustment", "internal/ledger/posting.go", "if rate == nil || diff.IsZero() || largest < 0 {", "if true {"),
 ("no rate applied", "internal/ledger/posting.go", "out[i].BaseAmount = core.Times(l.Amount, *rate, baseScale)", "out[i].BaseAmount = l.Amount"),
 ("late fact not postponed", "internal/periods/periods.go", "\t\tif p.State == Open {\n\t\t\treturn date, nil", "\t\tif p.State == Open || true {\n\t\t\treturn date, nil"),
 ("missing mapping gives up", "internal/intake/receive.go", "return work.Wait(err)", "return work.Permanent(err)"),
 ("no receivable.formed", "internal/openitems/openitems.go", "if err != nil || n.Kind != \"receivable\" {", "if true {"),
 ("receivable at net", "internal/intake/invoice.go", "Currency: inv.Currency, Amount: inv.Totals.Gross,", "Currency: inv.Currency, Amount: inv.Totals.Net,"),
 ("due date not the invoice's", "internal/intake/invoice.go", "due := inv.InvoiceDate", "due := \"2030-01-01\""),
 ("Read answers nothing", "internal/facts/facts.go", "WHERE fact_id = ANY($1::uuid[])`, asked)", "WHERE false AND fact_id = ANY($1::uuid[])`, asked)"),
 ("settled state ignored", "internal/openitems/records.go", "CASE WHEN o.state = 'open' AND o.amount = o.settled THEN 'settled' ELSE o.state END", "'settled'"),
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
