"""C5 P3c: erp/costing's price sources and adjustments. Each mutation must turn the costing integration tests red."""
import subprocess, sys, pathlib

S = "internal/layers/sources.go"
M = [
 ("LY02: a policy layer ignores its basis", S, "|| l.Base.Kind == SourceBasis {", "|| true {"),
 ("LY02: the basis replaces the invoiced units too", S, "\t\tstretches := l.uncovered()\n", "\t\tstretches := []methods.Range{{Start: \"0\", Quantity: l.Quantity}}\n"),
 ("LY02: no conversion", "internal/sources/sources.go", "return core.Mul(price, rate.Rate), rate, nil", "return price, rate, nil"),
 ("LY03: a kept confirmation not taken by its new layer", S, "func applyPending(ctx context.Context, tx db.Tx, l *layer) error {\n", "func applyPending(ctx context.Context, tx db.Tx, l *layer) error {\n\treturn nil\n"),
 ("LY03: the adjustment dated by something else", S, "core.FactOf(x.MovementID, c.FactID, core.FactReplaced), c.Date, c.SupplierID)", "core.FactOf(x.MovementID, c.FactID, core.FactReplaced), \"2026-11-01\", c.SupplierID)"),
 ("LY03: no supplier", S, "core.FactOf(x.MovementID, c.FactID, core.FactReplaced), c.Date, c.SupplierID)", "core.FactOf(x.MovementID, c.FactID, core.FactReplaced), c.Date, nil)"),
 ("LY04: a reversal before its confirmation forgotten", S, "reversed, data) VALUES ($1, $2, $3, $4, $5, $6, EXISTS (SELECT 1 FROM reversal WHERE confirmed_fact_id = $1), $7)", "reversed, data) VALUES ($1, $2, $3, $4, $5, $6, false, $7)"),
 ("LY05: a withdrawn basis used", "internal/layers/layers.go", "\t\tAND NOT EXISTS (SELECT 1 FROM basis_withdrawal w WHERE w.receipt_line_id = b.receipt_line_id)`", "`"),
 ("AD02: moving average all into the value", "internal/methods/methods.go", "inventory = core.Amount(core.Quo(core.Mul(total, in), qty), scale)", "inventory = core.Amount(total, scale)"),
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
