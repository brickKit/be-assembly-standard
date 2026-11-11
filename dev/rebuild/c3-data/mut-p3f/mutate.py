"""P3f mutation check (the full recovery's checks): each mutation must turn the payment integration tests red.
Run from the payment component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

K = "internal/requests/checks.go"
M = [
 ("a confirmed claim reported", K, 'if state == "confirmed" || reported[h.request] {', "if reported[h.request] {"),
 ("a dropped claim not reported", K, 'if state == "confirmed" || reported[h.request] {', 'if state != "" || reported[h.request] {'),
 ("only drafts asked", K, "WHERE r.state = 'ready' AND l.claim_id IS NOT NULL", "WHERE r.state = 'draft' AND l.claim_id IS NOT NULL"),
 ("statement lines not audited by line", "internal/statements/statements.go", "if err := core.Change(m, ctx, tx, actor, core.OpReconcile, core.Statements, id, line); err != nil {", "if err := core.Change(m, ctx, tx, actor, core.OpReconcile, core.Statements, a.ID, line); err != nil {"),
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
