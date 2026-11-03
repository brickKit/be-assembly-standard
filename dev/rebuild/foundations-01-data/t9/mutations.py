#!/usr/bin/env python3
"""Foundations item 1, T9: each bad variant of reference models 13, 14 and 37 as a change to be-sdk-go, run against
the tests that must catch it, the file restored after. Run from be-sdk-go with BE_SDK_TEST_PG_ADMIN and
BE_SDK_TEST_NATS_URL set: python3 <this file> [part of a variant's name] > mutations.out"""
import pathlib
import subprocess
import sys

# (model, variant, file, old text, new text, package, tests)
GUARD = """const guard = `id = $1 AND state = 'running' AND epoch = $2 AND claim_db_generation = $3 AND claim_db_timeline = $4
	AND (claim_db_generation, claim_db_timeline) = (SELECT generation, timeline FROM be_current_db_epoch())`"""
WORK = ("TestACrashedReplicasItemIsTakenOverAfterItsLease|TestATakenOverHolderCanCommitNothing|"
        "TestNonIdempotentCallsAreNeverSentTwice|TestALostClaimCannotCommitUnderAReusedCounter|TestPurgeKeepsWhatIsNotYetDue|"
        "TestRetriesThenDeadWithItsDeadLetter|TestASingletonContinuesFromItsCommittedProgress")
PROJ = ("TestProjectionApplyVectors|TestAlignMatchesSource|TestOlderAlignmentDiscarded|TestWrittenDuringAlignment|"
        "TestApplyAndRepair|TestInputsForANewRecordAreSerialized|TestALargerEpochIsAdoptedThroughAnAlignment|"
        "TestANewEpochsInputOverwritesAnOlderEpochsRow")
MUTATIONS = [
    ("13", "insert-only claim (no takeover)", "work/runner.go",
     "WHERE job = ANY($1) AND state = 'running' AND lease_until <= now()", "WHERE false", "./work/", WORK),
    ("13", "the completion mark in a separate transaction", "work/run.go",
     "func (r *Run) exec(ctx context.Context, set string, extra []any, fn func(context.Context, db.Tx) error) error {\n",
     "func (r *Run) exec(ctx context.Context, set string, extra []any, fn func(context.Context, db.Tx) error) error {\n"
     "\tif fn != nil {\n\t\tif err := r.db.BackgroundTx(ctx, fn); err != nil {\n\t\t\treturn err\n\t\t}\n\t\tfn = nil\n\t}\n",
     "./work/", WORK),
    ("13", "no epoch check on commit", "work/run.go", GUARD,
     "const guard = `id = $1 AND state = 'running' AND $2::bigint IS NOT NULL AND $3::bigint IS NOT NULL AND $4::bigint IS NOT NULL`",
     "./work/", WORK),
    ("13", "a non-idempotent call resent on takeover", "work/runner.go",
     "if Effect(effect) == NonIdempotentExternal && unknown {", "if false && Effect(effect) == NonIdempotentExternal && unknown {",
     "./work/", WORK),
    ("13", "cleanup without the watermark", "work/operator.go",
     "\n\t\t\t\tAND run_at <= (SELECT watermark_at FROM be_cron_watermark m WHERE m.job = w.job)))", "))", "./work/", WORK),
    ("13", "an ambiguous error treated as retryable (the flag cleared)", "work/runner.go",
     "case r.job.Effect == NonIdempotentExternal && k != \"not_effective\" && w.unknown(ctx, r):",
     "case false && r.job.Effect == NonIdempotentExternal && k != \"not_effective\" && w.unknown(ctx, r):", "./work/", WORK),
    ("14", "strict-greater rule only (R04)", "projection/projection.go",
     "kind == Full && cur.State == Incomplete && v >= cur.NeedVersion:", "kind == Full && cur.State == Incomplete && v > cur.NeedVersion:",
     "./projection/", PROJ),
    ("14", "a partial event applied and marked complete", "projection/projection.go",
     "\tcase kind == Partial && v > cur.Version:\n\t\treturn Row{State: Incomplete, Version: v, NeedVersion: v}, MergeAndFetch",
     "\tcase kind == Partial && v > cur.Version:\n\t\treturn Row{State: Complete, Version: v}, Overwrite", "./projection/", PROJ),
    ("14", "a deletion removes the row instead of a tombstone", "projection/projection.go",
     "func (p Projection) write(ctx context.Context, tx db.Tx, in Input, cur *Row, next Row, action string) (Outcome, error) {\n",
     "func (p Projection) write(ctx context.Context, tx db.Tx, in Input, cur *Row, next Row, action string) (Outcome, error) {\n"
     "\tif next.State == Tombstone {\n\t\t_, err := tx.Exec(ctx, \"DELETE FROM be_projection WHERE projection = $1 AND record_id = $2\", p.Name, in.RecordID)\n"
     "\t\treturn Outcome{Changed: true}, err\n\t}\n", "./projection/", PROJ),
    ("14", "the re-fetch overwrites unconditionally (rows written meanwhile go backwards)", "projection/align.go",
     "\t\t\tWHERE be_projection.aligned_gen IS DISTINCT FROM $8 OR be_projection.version < excluded.version`,", "\t\t\t`,",
     "./projection/", PROJ),
    ("14", "no epoch (versions compared across a failover)", "projection/projection.go",
     "\t\tr.Old = deref(impl) != in.Impl || deref(epoch) != in.Epoch", "\t\tr.Old = false", "./projection/", PROJ),
    ("14", "snapshots accepted only by version", "projection/align.go",
     "\t\t\tWHERE be_projection.aligned_gen IS DISTINCT FROM $8 OR be_projection.version < excluded.version`,",
     "\t\t\tWHERE be_projection.version < excluded.version`,", "./projection/", PROJ),
    ("37", "claims compare the claim counter only", "work/run.go", GUARD,
     "const guard = `id = $1 AND state = 'running' AND epoch = $2 AND $3::bigint IS NOT NULL AND $4::bigint IS NOT NULL`",
     "./work/", WORK),
    ("37", "the row's claim epoch compared with the current one, not the holder's own", "work/run.go", GUARD,
     "const guard = `id = $1 AND state = 'running' AND epoch = $2 AND $3::bigint IS NOT NULL AND $4::bigint IS NOT NULL\n"
     "\tAND (claim_db_generation, claim_db_timeline) = (SELECT generation, timeline FROM be_current_db_epoch())`",
     "./work/", WORK),
]


def test(pkg: str, tests: str) -> list[str]:
    r = subprocess.run(["go", "test", "-count=1", "-timeout", "180s", "-tags", "integration", "-run", tests, pkg],
                       capture_output=True, text=True)
    return [l for l in (r.stdout + r.stderr).splitlines() if l.startswith(("--- FAIL", "ok ", "FAIL\t", "# "))
            or "build failed" in l]


def main() -> None:
    only = sys.argv[1] if len(sys.argv) > 1 else ""  # a part of a variant's name: run only those
    print("=== unchanged")
    for pkg, tests in (("./work/", WORK), ("./projection/", PROJ)):
        print("\n".join(test(pkg, tests)))
    for model, variant, f, old, new, pkg, tests in MUTATIONS:
        if only not in variant:
            continue
        p = pathlib.Path(f)
        orig = p.read_text()
        if old not in orig:
            sys.exit(f"model {model} {variant}: the text to change is not in {f}")
        p.write_text(orig.replace(old, new, 1))
        try:
            print(f"=== model {model}: {variant}")
            print("\n".join(test(pkg, tests)), flush=True)
        finally:
            p.write_text(orig)


main()
