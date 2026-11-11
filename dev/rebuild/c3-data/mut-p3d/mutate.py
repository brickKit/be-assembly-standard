"""P3d mutation check (transfers, bank charges, interest): each mutation must turn the payment integration tests red.
Run from the payment component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

A = "internal/entries/actions.go"
E = "internal/entries/entries.go"
M = [
 ("the maker approves", A, "if e.MakerID == actor {", "if false {"),
 ("a transfer across currencies", E, "if to.Currency != from.Currency {", "if to.Currency != from.Currency && false {"),
 ("a transfer to itself", E, "case in.Kind == \"transfer\" && *in.ToBankAccountID == in.BankAccountID:", "case false:"),
 ("a charge with a to-account", E, "case in.Kind != \"transfer\" && in.ToBankAccountID != nil:", "case false:"),
 ("a transfer posted at once", A, 'rule, roles, to := "fund_transfer_out", []string{"in_transit", "bank"}, InTransit', 'rule, roles, to := "fund_transfer_out", []string{"in_transit", "bank"}, Posted'),
 ("an arrival before the transfer", A, "|| *in.ArrivedOn < cur.EntryDate)", ")"),
 ("no arrival fact", A, 'f := fact(e, "fund_transfer_in", *in.ArrivedOn, []string{"bank", "in_transit"}, rate)\n\t\tif err := f.Publish(m, ctx, tx); err != nil {', 'f := fact(e, "fund_transfer_in", *in.ArrivedOn, []string{"bank", "in_transit"}, rate)\n\t\tif err := error(nil); err != nil {'),
 ("interest without its income role", A, 'rule, roles, to = "bank_interest", []string{"bank", "income"}, Posted', 'rule, roles, to = "bank_interest", []string{"bank"}, Posted'),
 ("no rate snapshot", A, "f := fact(e, rule, e.EntryDate, roles, rate)", "f := fact(e, rule, e.EntryDate, roles, nil)"),
 ("a posted entry cancelled", "internal/entries/lifecycle.go", 'Posted:    core.RefuseCell("BE04", "a posted entry is not cancelled"),', 'Posted:    core.MoveCell("BE04", Cancelled, core.OpEntryEdit),'),
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
