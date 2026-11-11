"""C5 P0b: erp/inventory's StockService.Movements. Each mutation must turn the inventory integration tests red."""
import subprocess, sys, pathlib

V = "internal/movements/valuation.go"
M = [
 ("out of order", V, "ORDER BY m.valuation_seq LIMIT $5", "ORDER BY m.valuation_seq DESC LIMIT $5"),
 ("the limit ignored", V, "limit = min(limit, 1000)", "limit = 1000"),
 ("from the first, not from the one asked", V, "AND m.valuation_seq >= $4 ORDER BY", "AND $4::bigint IS NOT NULL ORDER BY"),
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
