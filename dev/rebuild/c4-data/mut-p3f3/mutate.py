"""P3f-3 mutation check (manual open items): each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

I = "internal/manualitems/manual.go"
M = [
 ("the maker approves", I, "if maker == actor { // GuardNotMaker", "if false { // GuardNotMaker"),
 ("a pending item is claimable", "internal/claims/claims.go", "|| o.State == \"pending_approval\" || o.State == \"cancelled\" {", "|| o.State == \"cancelled\" {"),
 ("no receivable formed on approval", I, "if err := openitems.Formed(m, ctx, tx, out, nil); err != nil {", "if err := error(nil); err != nil {"),
 ("the counter on the wrong side", I, "Side: ledger.Rules[rule][\"counter\"]", "Side: ledger.Rules[rule][o.Kind]"),
 ("a foreign currency registered", I, "if in.Currency != le.BaseCurrency {", "if false {"),
 ("a heading as the counter", I, "if err := ledger.Postable(ctx, tx, in.LegalEntityID, in.CounterAccountCode); err != nil {", "if err := error(nil); err != nil {"),
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
