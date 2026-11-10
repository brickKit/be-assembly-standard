"""P3f-2 mutation check (accounting facts): each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

A = "internal/intake/accounting.go"
M = [
 ("accounting facts not posted", "internal/intake/receive.go", "case strings.HasSuffix(typ, core.AccountingFactSuffix):\n\t\treturn postAccounting", "case false:\n\t\treturn postAccounting"),
 ("no partner nor department on the lines", A, "lines[i].PartnerID, lines[i].DepartmentID = af.PartnerID, af.Dimensions.DepartmentID", "_ = i"),
 ("a late fact not postponed", A, "date, err := periods.PostingDate(m, ctx, tx, f.LegalEntityID, af.PostingDate)", "date, err := periods.Month(af.PostingDate)+af.PostingDate[7:], error(nil)"),
 ("the rate ignored", A, "Lines: ledger.Convert(lines, af.Currency, rate, f.BaseScale)})", "Lines: ledger.Convert(lines, af.Currency, nil, f.BaseScale)})\n\t_ = rate"),
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
