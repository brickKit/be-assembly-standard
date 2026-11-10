"""P3e mutation check: each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

C = "internal/claims/"
M = [
 ("claims beyond the available", C+"claims.go", "if core.Cmp(amount, o.Available) > 0 { // GuardAvailable", "if false { // GuardAvailable"),
 ("another amount is the same claim", C+"claims.go", "if r.OpenItemID != item.ID || core.Cmp(r.Amount, amount) != 0 {", "if false {"),
 ("a receivable is claimed", C+"claims.go", "if (o.Kind != \"payable\" && o.Kind != \"credit_balance\") || o.State", "if o.State"),
 ("renewal keeps the expiry", C+"claims.go", "if _, err := tx.Exec(ctx, `UPDATE pay_claim SET expires_at = $2,", "if _, err := tx.Exec(ctx, `UPDATE pay_claim SET expires_at = expires_at + 0 * interval '1 s' + ($2::timestamptz - $2::timestamptz),"),
 ("expiry ignores a renewal", C+"claims.go", "if d.Effect != core.Move || r.ExpiresAt == nil || time.Now().Before(*r.ExpiresAt) { // GuardPastExpiry", "if d.Effect != core.Move { // GuardPastExpiry"),
 ("release keeps the amount claimed", C+"claims.go", "if d.To == Expired || d.To == Released {", "if d.To == Expired {"),
 ("expiry keeps the amount claimed", C+"claims.go", "if d.To == Expired || d.To == Released {", "if d.To == Released {"),
 ("no expiry queued", C+"claims.go", "_, err := m.RT.Work.EnqueueAt(ctx, tx, JobExpireClaim, expireArgs{ClaimID: id}, at)", "_, err := \"\", error(nil)\n\t_ = at"),
 ("renewing an overdue claim", C+"claims.go", "if r.ExpiresAt == nil || !time.Now().Before(*r.ExpiresAt) {", "if r.ExpiresAt == nil {"),
 ("due items ignore the cursor", C+"due.go", "AND (due_date, id) > ($5::date, $6::uuid)", "AND ($5::date, $6::uuid) IS NOT NULL"),
 ("due items with nothing available", C+"due.go", "AND amount - settled - pay_claimed > 0 AND", "AND"),
 ("due items ignore the date", C+"due.go", "AND due_date <= $3::date", "AND $3::date IS NOT NULL"),
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
