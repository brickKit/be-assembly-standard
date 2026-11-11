"""P3c mutation check (payment proposals and requests): each mutation must turn the payment integration tests red.
Run from the payment component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

A = "internal/requests/actions.go"
W = "internal/requests/renewal.go"
M = [
 ("the applicant approves", A, 'if cur.ApplicantID != nil && *cur.ApplicantID == actor {\n\t\treturn cur, core.ErrApprover.New("the request was submitted by " + actor + ": another approves it")', 'if false {\n\t\treturn cur, core.ErrApprover.New("the request was submitted by " + actor + ": another approves it")'),
 ("the applicant releases", A, 'if cur.ApplicantID != nil && *cur.ApplicantID == actor {\n\t\treturn cur, core.ErrApprover.New("the request was submitted by " + actor + ": another releases it")', 'if false {\n\t\treturn cur, core.ErrApprover.New("the request was submitted by " + actor + ": another releases it")'),
 ("no payee check", A, "if err := payable(m, ctx, cur); err != nil {", "if err := error(nil); err != nil {"),
 ("claims kept after a refused submission", A, "if rerr := releaseAll(m, ctx, made); rerr != nil {", "if rerr := error(nil); rerr != nil {"),
 ("no confirmation on release", A, "if err := masterdata.Confirm(m, ctx, c); err != nil {", "if err := error(nil); err != nil {"),
 ("claims kept on rejection and cancellation", A, "if err := releaseAll(m, ctx, cur.claims()); err != nil {\n\t\treturn cur, err\n\t}\n\tto := Draft", "if err := error(nil); err != nil {\n\t\treturn cur, err\n\t}\n\tto := Draft"),
 ("the paid amount all on the first line", A, "		p := l.Amount\n", "		p := left\n"),
 ("a claim carries its whole amount", A, "f.Claims = append(f.Claims, facts.ClaimAmount{ClaimID: *l.ClaimID, Amount: share})", "f.Claims = append(f.Claims, facts.ClaimAmount{ClaimID: *l.ClaimID, Amount: l.Amount})"),
 ("more paid than requested", A, "if core.Cmp(paid, cur.Amount) > 0 {", "if false {"),
 ("a lapse ignored", W, "return lapse(m, ctx, r, a.ClaimID)", "return nil"),
 ("no renewal queued", W, "_, err = m.RT.Work.EnqueueAt(ctx, tx, JobRenewClaim, renewArgs{RequestID: request, ClaimID: claim}, renewAt(at))", "_ = renewAt(at)"),
 ("a return refers to nothing", A, 'f.FactID, f.Kind, f.ReversesFactID, f.RecordedAt = reversal, "reversal", &original, facts.Now()', 'f.FactID, f.Kind, f.ReversesFactID, f.RecordedAt = reversal, "reversal", func() *string { _ = original; return nil }(), facts.Now()'),
 ("a paid request executed again", "internal/requests/lifecycle.go", 'Paid:      core.IgnoreCell("PR05"),', 'Paid:      core.MoveCell("PR05", Paid, core.OpRequestExecute),'),
 ("a released claim still expires", A, "if _, err := tx.Exec(ctx, `UPDATE payment_request_line SET claim_expires_at = NULL WHERE request_id = $1`, r.ID); err != nil {", "if _, err := tx.Exec(ctx, `SELECT $1::uuid`, r.ID); err != nil {"),
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
