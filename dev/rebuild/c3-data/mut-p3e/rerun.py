"""P3e mutation check (statement lines and reconciliation): each mutation must turn the payment integration tests red.
Run from the payment component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

G = "internal/matching/matching.go"
S = "internal/statements/statements.go"
M = [
 ("a reversed receipt matches", G, "FROM receipt r WHERE r.state = 'received'", "FROM receipt r WHERE r.state IN ('received', 'reversed')"),
 ("a returned payment matches", G, "FROM payment_request p WHERE p.state = 'paid'", "FROM payment_request p WHERE p.state IN ('paid', 'returned')"),
 ("the amount not compared", G, "AND d.amount = $4::numeric AND NOT EXISTS", "AND $4::numeric IS NOT NULL AND NOT EXISTS"),
 ("a document matched twice", G, "WHERE d.type = $1 AND d.id = $2 AND d.account = $3 AND d.amount = $4::numeric AND NOT EXISTS (SELECT 1", "WHERE d.type = $1 AND d.id = $2 AND d.account = $3 AND d.amount = $4::numeric AND EXISTS (SELECT 1 UNION SELECT 1"),
 ("the account not compared", G, "WHERE d.type = $1 AND d.id = $2 AND d.account = $3 AND", "WHERE d.type = $1 AND d.id = $2 AND $3::text IS NOT NULL AND"),
 ("a reference registered twice", S, "if tag.RowsAffected() == 0 {", "if tag.RowsAffected() < 0 {"),
 ("a receipt does not find its line", "internal/receipts/receipts.go", "return core.IDResult(id), matching.Document(ctx, tx, a.ID, &in.BankReference)", "_ = matching.Document\n\t\treturn core.IDResult(id), nil"),
 ("an entry from a line does not match it", "internal/entries/actions.go", "if e.StatementLineID == nil {", "if e.StatementLineID == nil || true {"),
 ("an entry made twice from a line", S, "if drafts > 0 {", "if drafts < 0 {"),
 ("the reconciliation on another account", G, "WHERE d.account = $1 AND d.date BETWEEN", "WHERE d.account <> $1 AND d.date BETWEEN"),
 ("a difference resolved without a note", S, 'if command == Resolve && (in.Reason == nil || strings.TrimSpace(*in.Reason) == "") {', "if false {"),
]
survived = []
ONLY = set(sys.argv[1:])
for mut in [x for x in M if not ONLY or x[0] in ONLY]:
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
