"""C5 P3b: erp/costing's policy and valuation sequence. Each mutation must turn the costing integration tests red."""
import subprocess, sys, pathlib

P = "internal/sequence/process.go"
M = [
 ("VS02: the lowest kept number, not the next", P, "AND epoch = $2 AND seq = $3`,\n\t\t\ts.ID, s.Epoch, s.NextSeq).Scan(&factID, &data)",
  "AND epoch = $2 AND seq >= $3 ORDER BY seq LIMIT 1`,\n\t\t\ts.ID, s.Epoch, s.NextSeq).Scan(&factID, &data)"),
 ("VS04: a renumbered movement valued again", P, "\tif valued { // VS04", "\tif valued && false { // VS04"),
 ("VS04: stops when not ahead", P, "if cur.NextSeq-1 > last {", "if cur.NextSeq-1 >= last {"),
 ("VS03: the gap never read back", P, "case s.State == WaitingGap && s.gapDue:", "case s.State == WaitingGap && s.gapDue && false:"),
 ("LY01: the policy price from the earliest layer", "internal/layers/layers.go", "ORDER BY ordinal DESC LIMIT 1", "ORDER BY ordinal LIMIT 1"),
 ("LY01: a receipt never waits for its basis", "internal/layers/layers.go", "\t\tcase !policy:\n", "\t\tcase !policy && false:\n"),
 ("IS01: an issue rounded to whole units, not the currency's places", "internal/issues/issues.go", "cost = core.Amount(core.Quo(core.Mul(qty, s.Value), onHand), s.Scale)",
  "cost = core.Amount(core.Mul(qty, core.Quo(s.Value, s.Quantity)), 0)"),
 ("PO01: a change in use allowed", "internal/policies/policies.go", "\tcase p.InUse:\n", "\tcase p.InUse && false:\n"),
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
