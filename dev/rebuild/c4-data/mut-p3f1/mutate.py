"""P3f-1 mutation check (settlement): each mutation must turn the finance integration tests red.
Run from the finance component root with BE_SDK_TEST_PG_ADMIN and BE_SDK_TEST_NATS_URL set."""
import subprocess, sys, pathlib

S = "internal/settlement/"
M = [
 ("receipts across legal entities", S+"fund.go", "WHERE legal_entity_id = $1 AND partner_id = $2", "WHERE $1::uuid IS NOT NULL AND partner_id = $2"),
 ("not the earliest due first", S+"fund.go", "if order[i].DueDate != order[j].DueDate {", "if false {"),
 ("no credit balance for the rest", S+"fund.go", "if core.Cmp(rest, \"0\") > 0 { // ST03: the rest", "if false { // ST03: the rest"),
 ("an unconfirmed claim is used", S+"fund.go", "usable := r.State == claims.Confirmed && ok", "usable := r.State != claims.None && ok"),
 ("formalizing keeps the claim", "internal/claims/claims.go", "if err := adjust(ctx, tx, r.OpenItemID, core.Minus(\"0\", r.Amount)); err != nil {\n\t\treturn r, err\n\t}\n\tafter, err := Get(ctx, tx, r.ClaimID)\n\tif err != nil {\n\t\treturn after, err\n\t}\n\treturn after, change(m, ctx, tx, actor, after)\n}\n\n// ReverseFormalized", "after, err := Get(ctx, tx, r.ClaimID)\n\tif err != nil {\n\t\treturn after, err\n\t}\n\treturn after, change(m, ctx, tx, actor, after)\n}\n\n// ReverseFormalized"),
 ("a reversal keeps the claim formalized", S+"reversal.go", "if _, err := claims.ReverseFormalized(m, ctx, tx, r, t.amount, f.Source); err != nil {", "if _, err := r, error(nil); err != nil {"),
 ("a reversal reports reduced", S+"allocation.go", "case a.direction == \"reverse\":\n\t\ttyp = core.ReceivableReopened", "case false:\n\t\ttyp = core.ReceivableReopened"),
 ("a reversal keeps the credit balance", S+"reversal.go", "UPDATE open_item SET state = 'cancelled',", "UPDATE open_item SET state = state,"),
 ("the mirror keeps the sides", S+"reversal.go", "lines[i].Side = map[string]string{\"debit\": \"credit\", \"credit\": \"debit\"}[l.Side]", "lines[i].Side = l.Side"),
 ("a reversal before its fact posts nothing", S+"reversal.go", "if err != nil || state != \"posted\" || original == nil {\n\t\treturn \"\", core.ErrWaitForOriginal", "if err != nil || state != \"posted\" || original == nil {\n\t\treturn \"\", nil"),
 ("the settled fact not published", S+"allocation.go", "if err := core.Fact(m, ctx, tx, core.OpenItemSettled, id,", "if err := func(...any) error { return nil }(m, ctx, tx, core.OpenItemSettled, id,"),
 ("a cleared receivable reports reduced", S+"allocation.go", "case core.Cmp(after.OpenBalance, \"0\") == 0:", "case false:"),
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
        r = subprocess.run(["go", "test", "-count=1", "-tags", "integration", "./itest/"], capture_output=True, text=True, timeout=240); print("done", name, flush=True)
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
