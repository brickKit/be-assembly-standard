"""Mutation runs for be-sdk-go's JudgeMany (P9.24): each mutant replaces one exact snippet, builds, runs the
named tests, records which fail and on what, and restores the file. Run from tools/be-sdk-go with the integration env."""
import subprocess, sys, re

MUTANTS = [
    ("projection/watermark.go", "in.Quarantined = in.Quarantined || q[s]", "in.Quarantined = in.Quarantined || (q[s] && false)", "projection", "TestAFailingEventQuarantinesItsSubjectsOnly"),
    ("projection/watermark.go", "in.Row = &JudgedRow{State: r.state, Adopted: r.impl == impl && r.epoch == epoch}", "in.Row = &JudgedRow{State: r.state, Adopted: true}", "projection", "Test.*Epoch.*|TestARollback.*|TestAnotherSystem.*|TestAnUnknownInstance.*|TestJudgeMany.*"),
    ("projection/watermark.go", "\t\tif j.Verdict != Usable {\n\t\t\tj.Data = nil\n\t\t}", "", "projection", "TestJudgeManyAtTwoFreshnesses"),
    ("projection/watermark.go", "if Judge(base) != Unprovable { // the source rows", "if true { // the source rows", "projection", "TestJudgeManyAtTwoFreshnesses"),
    ("projection/watermark.go", "WHEN count(*) FILTER (WHERE echo_mp IS NULL) > 0 OR count(*) = 0 THEN NULL", "WHEN count(*) = 0 THEN NULL", "projection", "TestAWatermarkProvesTheProjectionFresh|TestAHoleStopsTheContiguousPosition|TestJudgeMany.*"),
    ("projection/watermark.go", "time.Duration(*age*float64(time.Second))", "time.Duration(*age)", "projection", "TestJudgeManyAtTwoFreshnesses"),
]

only = {int(a) for a in sys.argv[1:]}
for i, (path, old, new, pkg, tests) in enumerate(MUTANTS):
    if only and i not in only:
        continue
    src = open(path).read()
    if src.count(old) != 1:
        print(f"== {path}: pattern found {src.count(old)} times, skipped: {old!r}"); continue
    open(path, "w").write(src.replace(old, new))
    try:
        print(f"== mutant {path}: {old!r} -> {new!r}")
        b = subprocess.run(["go", "vet", "-tags", "integration", "./" + pkg], capture_output=True, text=True)
        if b.returncode:
            print("   does not compile:", b.stderr.strip().splitlines()[-1]); continue
        r = subprocess.run(["go", "test", "-count=1", "-tags", "integration", "./" + pkg, "-run", tests],
                           capture_output=True, text=True)
        out = r.stdout + r.stderr
        fails = sorted(set(re.findall(r"^--- FAIL: (\S+)", out, re.M)))
        msgs = [l.strip() for l in out.splitlines() if re.search(r"Error:|Messages:|expected|actual  :", l)][:6]
        print("   failed:", fails or "NONE (survived)")
        for m in msgs:
            print("     ", m[:200])
    finally:
        open(path, "w").write(src)
