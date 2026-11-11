"""C5 P3e: erp/costing's FIFO issues, purchase returns and levelling. Each mutation must turn the costing integration tests red."""
import subprocess, sys, pathlib

T, I = "internal/layers/take.go", "internal/issues/issues.go"
M = [
 ("IS01: FIFO from the newest layer", T, "ORDER BY ordinal`, s.ID)", "ORDER BY ordinal DESC`, s.ID)"),
 ("IS01: FIFO at the base price only", T, "\t\tif core.Cmp(to, from) > 0 {", "\t\tif false && core.Cmp(to, from) > 0 {"),
 ("AD02: FIFO all in stock", "internal/methods/methods.go", "inStock = core.Sum(inStock, core.Minus(r.Quantity, gone))", "inStock = core.Sum(inStock, r.Quantity)"),
 ("RT01: FIFO return at the layer's average", I, "\tcase s.Method == core.MethodFIFO:\n\t\tvalue, taken, err = layers.TakeFromLayer", "\tcase false:\n\t\tvalue, taken, err = layers.TakeFromLayer"),
 ("RT01: moving average limited", I, "out.Known, out.Limited = true, method == core.MethodFIFO", "out.Known, out.Limited = true, method != \"\""),
 ("RT01: the limit is not the units in stock", I, "out.Quantity = core.Plain(o.InStock)", "out.Quantity = core.Plain(o.UnitCost)"),
 ("RT01: anyone asks", "costing/module.go", "\"ReturnLimit\": {Operation: core.OpSysRead, Callers: []string{core.Purchase}}", "\"ReturnLimit\": {Operation: core.OpSysRead, Callers: []string{grpcx.AnyComponent}}"),
 ("IS02: no levelling", I, "\tif core.Cmp(before, \"0\") >= 0 {\n\t\treturn nil", "\tif true {\n\t\treturn nil"),
 ("IS02: the levelling's direction swapped", I, "\tif core.Cmp(diff, \"0\") < 0 {\n\t\tneg", "\tif core.Cmp(diff, \"0\") > 0 {\n\t\tneg"),
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
