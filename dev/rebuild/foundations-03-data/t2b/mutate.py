"""Mutation runs for be-sdk-go's record reads (P9.30-P9.33): each mutant replaces one exact snippet, builds, runs the
named tests, records which fail and on what, and restores the file. Run from tools/be-sdk-go with the integration env."""
import subprocess, sys, re

MUTANTS = [
    ("events/records.go", "if !contains(s.Records.Readers, caller) {", "if false {", "events", "TestOnlyTheDeclaredReadersMayRead"),
    ("events/records.go", "coalesce((SELECT last_seq FROM", "coalesce((SELECT 0::bigint FROM", "events", "TestAReadAnswersEveryIDInOrder"),
    ("events/records.go", "if tok.Impl != \"\" && (tok.Impl != r.Impl || tok.Epoch != snap.epoch) {", "if false {", "events", "TestASnapshotPageTokenIsBoundToTheEpoch"),
    ("events/records.go", "recs, err = s.Records.Page(ctx, tx, tok.After, RecordPage+1)", "recs, err = s.Records.Page(ctx, tx, tok.After, RecordPage)", "events", "TestASnapshotPagesByRecordID"),
    ("events/records.go", "if err != nil || len(b) <= MaxPayload {", "if err != nil || true {", "events", "TestABigRecordIsAClaimCheck"),
    ("events/records.go", "if len(ids) == 0 || len(ids) > RecordPage {", "if len(ids) == 0 {", "events", "TestAReadAnswersEveryIDInOrder"),
    ("events/stream.go", "if !contains(s.Records.Readers, c) {", "if false {", "events", "TestAWatermarkStreamDeclaresItsRecordReads"),
    ("events/stream.go", "if s.Records == nil {\n\t\t\treturn fmt.Errorf", "if false {\n\t\t\treturn fmt.Errorf", "events", "TestAWatermarkStreamDeclaresItsRecordReads"),
    ("projection/align.go", "if !d.Primary || d.Impl != want.Impl || d.Epoch != want.Epoch ||", "if false && (!d.Primary || d.Impl != want.Impl || d.Epoch != want.Epoch) ||", "projection", "TestOnlyTheAdoptedPrimaryIsUsed"),
    ("projection/align.go", "d.Epoch != want.Epoch ||", "false ||", "projection", "TestOnlyTheAdoptedPrimaryIsUsed"),
    ("projection/align.go", "\t\tif learn {\n\t\t\tif !from.Primary {", "\t\tif learn {\n\t\t\tif false {", "projection", "TestOnlyTheAdoptedPrimaryIsUsed"),
    ("projection/align.go", "\tif !from.Primary {\n\t\treturn 0, fmt.Errorf", "\tif false {\n\t\treturn 0, fmt.Errorf", "projection", "TestOnlyTheAdoptedPrimaryIsUsed"),
    ("projection/records.go", "if len(data) != ref.Claim.Size || hex.EncodeToString(sum[:]) != ref.Claim.SHA256 {", "if len(data) != ref.Claim.Size || hex.EncodeToString(sum[:]) == \"\" {", "projection", "TestRecordClientResolvesClaims"),
    ("projection/records.go", "if start > 0 && d != from {", "if false {", "projection", "TestRecordClientReadsInBatchesFromOneSource"),
    ("projection/records.go", "if r.GetRecordId() != part[i] {", "if false {", "projection", "TestRecordClientReadsInBatchesFromOneSource"),
    ("projection/watermark.go", "Identity{Deployment: w.Deployment, Impl: st.adopted.Impl, Epoch: st.adopted.Epoch}", "Identity{}", "projection", "TestALargerEpochIsAdoptedThroughAnAlignment|TestAWatermarkProvesTheProjectionFresh|TestTheAlignmentUsesOnlyTheAdoptedSourcesReads"),
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
