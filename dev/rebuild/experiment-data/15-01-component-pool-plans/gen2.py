"""Writes the second experiment: (1) the forwarder's read of unpublished rows behind published rows kept for the
redelivery retention (P6.12): 20 vs 20 000 published rows before 600 unpublished ones; (2) the work claim with a due
index that holds the job too. Each with the current indexes and the candidate ones, on a fresh schema with every SDK
migration and autovacuum off; eight executions to settle the plan, EXPLAIN ANALYZE, then the larger backlog, three
executions, EXPLAIN ANALYZE. Usage: python3 gen2.py <plan_cache_mode> <current|candidate> [analyze-small] > file.sql"""
import glob
import os
import sys

mode, which = sys.argv[1], sys.argv[2]
analyze_small = len(sys.argv) > 3 and sys.argv[3] == "analyze-small"  # analyzed once at the small backlog
here = os.path.dirname(os.path.abspath(__file__))
mig = sorted(glob.glob(os.path.join(here, "../../../../tools/be-protocol/migrations/*.up.sql")))
out = ["\\set ON_ERROR_STOP on", "\\pset pager off", "DROP SCHEMA IF EXISTS t3_probe CASCADE;", "CREATE SCHEMA t3_probe;",
       "SET search_path = t3_probe;", f"SET plan_cache_mode = {mode};"]
for m in mig:
    out.append(open(m).read())
if which == "candidate":
    out.append("""DROP INDEX be_outbox_unpublished;
CREATE INDEX be_outbox_unpublished ON be_outbox (stream, partition, epoch_generation, epoch_timeline, seq)
    WHERE seq IS NOT NULL AND published_at IS NULL;
DROP INDEX be_work_item_due_at;
CREATE INDEX be_work_item_due_at ON be_work_item (run_at, job) WHERE state IN ('pending', 'retry_wait');""")
for t in ("be_outbox", "be_work_item"):
    out.append(f"ALTER TABLE {t} SET (autovacuum_enabled = false);")

OUTBOX = """INSERT INTO be_outbox (event_id, stream, partition, type, occurred_at, record_id, version, projection, hops,
  payload, digest, seq, epoch_generation, epoch_timeline, published_at)
  SELECT gen_random_uuid(), 's', 0, 't.v1', now(), g::text, 1, 'full', 0, '\\x7b7d', 'd', g, 1, 1, {pub}
  FROM generate_series({a}, {b}) g;"""
UNPUB = """SELECT ord, event_id::text, type, occurred_at, record_id, version, projection,
		coalesce(legal_entity, ''), subjects, coalesce(causation::text, ''), hops, trace, payload, digest, seq,
		epoch_generation, epoch_timeline
		FROM be_outbox WHERE stream = $1 AND partition = $2 AND seq IS NOT NULL AND published_at IS NULL
		ORDER BY epoch_generation, epoch_timeline, seq LIMIT $3"""
WORK = """INSERT INTO be_work_item (id, job, kind, state, max_attempts, effect_class, operation_id, args, run_at)
  SELECT gen_random_uuid()::text, CASE WHEN g % 2 = 0 THEN 'bulk' ELSE 'other' END, 'queue', 'pending', 3, 'local',
  gen_random_uuid()::text, '{}'::jsonb, now() - g * interval '1 ms' FROM generate_series(@LO@, @HI@) g;"""
CLAIM = """WITH expired AS (
				SELECT id FROM be_work_item WHERE job = ANY($1) AND state = 'running' AND lease_until <= now()
				ORDER BY lease_until LIMIT 1 FOR UPDATE SKIP LOCKED),
			due AS (
				SELECT id FROM be_work_item WHERE job = ANY($1) AND state IN ('pending', 'retry_wait') AND run_at <= now()
					AND NOT EXISTS (SELECT 1 FROM expired)
				ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED),
			c AS (SELECT id FROM expired UNION ALL SELECT id FROM due)
			UPDATE be_work_item w SET state = 'running', epoch = w.epoch + 1, attempts = w.attempts + 1, holder = $2,
				lease_until = now() + make_interval(secs => $3), claim_db_generation = e.generation,
				claim_db_timeline = e.timeline
			FROM c, be_current_db_epoch() e WHERE w.id = c.id
			RETURNING w.id"""


def settle_and_grow(name, stmt, args, small, grow):
    if analyze_small:
        out.append("ANALYZE be_outbox; ANALYZE be_work_item;")
    out.append(f"PREPARE {name} AS {stmt};")
    for _ in range(8):
        out.append(f"BEGIN; EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"\\echo ===== {name}: small")
    out.append(f"BEGIN; EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE {name}{args}; ROLLBACK;")
    out.extend(grow)
    for _ in range(3):
        out.append(f"BEGIN; EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"\\echo ===== {name}: large")
    out.append(f"BEGIN; EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"DEALLOCATE {name};")


# 20 published rows, then 600 unpublished; the larger: 20 000 published before the same 600 unpublished
out.append("TRUNCATE be_outbox;")
out.append(OUTBOX.format(a=1, b=20, pub="now()"))
out.append(OUTBOX.format(a=20001, b=20600, pub="NULL"))
settle_and_grow("unpublished", UNPUB, "('s', 0, 500)", 620, [OUTBOX.format(a=21, b=20000, pub="now()")])
out.append("TRUNCATE be_work_item;")
out.append(WORK.replace("@LO@", "1").replace("@HI@", "20"))
settle_and_grow("claim", CLAIM, "('{bulk,other}', 'h', 30)", 20, [WORK.replace("@LO@", "21").replace("@HI@", "20000")])
out.append("DROP SCHEMA t3_probe CASCADE;")
print("\n".join(out))
