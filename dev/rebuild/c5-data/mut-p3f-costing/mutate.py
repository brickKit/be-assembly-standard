"""C5 P3f: erp/costing's queries and recovery checks. Each mutation must turn the costing integration tests red."""
import subprocess, sys, pathlib

Q, K = "internal/layers/queries.go", "internal/sequence/checks.go"
M = [
 ("the layer list ignores in_stock", Q, '"legal_entity_id", "product_id", "source", "in_stock"}', '"legal_entity_id", "product_id", "source"}'),
 ("value_in_stock over the whole layer", Q, "l.rangeValue(l.Issued, core.Minus(l.Quantity, l.Issued))", "l.rangeValue(\"0\", l.Quantity)"),
 ("a FIFO valuation without its layers", "internal/sequence/scopes.go", "if err != nil || out.Method != core.MethodFIFO {", "if err != nil || true {"),
 ("the fact's trigger not kept", "internal/facts/cost.go", "c.MovementID, c.Rule, c.Date, c.Trigger.Kind, c.Trigger.FactID)", "c.MovementID, c.Rule, c.Date, facts0, c.MovementID)".replace("facts0", "\"movement\"")),
 ("negative stock misses -1", K, "WHERE quantity < 0 ORDER BY id", "WHERE quantity < -1 ORDER BY id"),
 ("waiting counts a day", K, "waiting_since < now() - interval '1 hour'", "waiting_since < now() - interval '1 day'"),
]
import os
if os.environ.get("ONLY"):
    M = [x for x in M if os.environ["ONLY"] in x[0]]
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
