"""P3b mutation check: each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

M = [
 ("unbalanced accepted", "internal/ledger/posting.go", "if !s.IsZero() {", "if false && !s.IsZero() {"),
 ("heading postable", "internal/ledger/accounts.go", "if !postable || state != \"active\" {", "if state != \"active\" {"),
 ("inactive postable", "internal/ledger/accounts.go", "if !postable || state != \"active\" {", "if !postable {"),
 ("maker approves", "internal/vouchers/vouchers.go", "if v.MakerID != nil && *v.MakerID == actor {", "if false {"),
 ("closed period posts", "internal/periods/periods.go", "if d := Lifecycle.Decide(p.State, PostManual); d.Effect == core.Refuse {", "if d := Lifecycle.Decide(p.State, PostManual); false {"),
 ("waiting voucher ignored", "internal/periods/periods.go", "if waiting > 0 {", "if waiting > 99 {"),
 ("earlier month ignored", "internal/periods/periods.go", "for m := first; m < month; m = next(m) {", "for m := first; m < first; m = next(m) {"),
 ("reopen without reason", "internal/periods/periods.go", "if command == Reopen && (in.Reason == nil", "if false && (in.Reason == nil"),
 ("one series for all periods", "internal/ledger/posting.go", "Code: \"JV\", Period: strings.ReplaceAll(v.Period, \"-\", \"\")}", "Code: \"JV\", Period: \"ALL\"}"),
 ("reversal keeps sides", "internal/vouchers/vouchers.go", "lines[i].Side = map[string]string{\"debit\": \"credit\", \"credit\": \"debit\"}[l.Side]", "lines[i].Side = l.Side"),
 ("mapping version ignored", "internal/ledger/mapping.go", "if tag.RowsAffected() == 0 {\n\t\t\tcur, err := mappingOf", "if tag.RowsAffected() == -1 {\n\t\t\tcur, err := mappingOf"),
 ("drafts in balances", "internal/ledger/balances.go", "v.state IN ('posted', 'reversed')", "v.state IN ('posted', 'reversed', 'draft', 'submitted')"),
 ("no posted fact", "internal/ledger/posting.go", "if err := core.Fact(m, ctx, tx, core.VoucherPosted,", "if err := func(...any) error { return nil }(m, ctx, tx, core.VoucherPosted,"),
]

survived = []
for name, path, old, new in M:
    p = pathlib.Path(path)
    src = p.read_text()
    assert src.count(old) == 1, (name, src.count(old))
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
        p.write_text(src)
    sys.stdout.flush()
print("MUTATION-DONE", len(M) - len(survived), "of", len(M), "killed")
sys.exit(1 if survived else 0)
