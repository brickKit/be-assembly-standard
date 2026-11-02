"""Writes plans.sql: the SDK's own "take the first rows" statements on a component's pool, as prepared statements
(pgx's statement cache when Prepared), on a fresh schema with every SDK migration of be-protocol and autovacuum off
(statistics that lag behind a backlog that just arrived). Each statement: a small backlog, eight executions (the
plan settles after five), EXPLAIN ANALYZE; then the backlog grows to 20 000, three executions, EXPLAIN ANALYZE.
Every execution is rolled back, so the backlog stays as built. Usage: python3 gen.py [plan_cache_mode] > plans.sql"""
import glob
import os
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "auto"
analyzed = len(sys.argv) > 2 and sys.argv[2] == "analyzed"
here = os.path.dirname(os.path.abspath(__file__))
mig = sorted(glob.glob(os.path.join(here, "../../../../tools/be-protocol/migrations/*.up.sql")))
out = ["\\set ON_ERROR_STOP on", "\\pset pager off", "DROP SCHEMA IF EXISTS t3_probe CASCADE;", "CREATE SCHEMA t3_probe;",
       "SET search_path = t3_probe;", f"SET plan_cache_mode = {mode};"]
for m in mig:
    out.append(f"-- {os.path.basename(m)}")
    out.append(open(m).read())
for t in ("be_outbox", "be_work_item", "be_audit_log"):
    out.append(f"ALTER TABLE {t} SET (autovacuum_enabled = false);")

OUTBOX = """INSERT INTO be_outbox (event_id, stream, partition, type, occurred_at, record_id, version, projection, hops,
  payload, digest, seq, epoch_generation, epoch_timeline)
  SELECT gen_random_uuid(), 's', 0, 't.v1', now(), g::text, 1, 'full', 0, '\\x7b7d', 'd', {seq}, {ep}, {ep}
  FROM generate_series({a}, {b}) g;"""
WORK = """INSERT INTO be_work_item (id, job, kind, state, max_attempts, effect_class, operation_id, args, run_at)
  SELECT gen_random_uuid()::text, CASE WHEN g % 2 = 0 THEN 'bulk' ELSE 'other' END, 'queue', 'pending', 3, 'local',
  gen_random_uuid()::text, '{{}}'::jsonb, now() - g * interval '1 ms' FROM generate_series({a}, {b}) g;"""
AUDIT = """INSERT INTO be_audit_log (id, occurred_at, category, operation, outcome, digest, seq, epoch_generation,
  epoch_timeline, record) SELECT gen_random_uuid(), now(), 'business_change', 'op', 'succeeded', 'd', {seq}, {ep}, {ep},
  '\\x7b7d' FROM generate_series({a}, {b}) g;"""

CASES = [
    ("outbox_number", "outbox", OUTBOX, dict(seq="NULL", ep="NULL"), 600,
     """WITH picked AS (
			SELECT ord, row_number() OVER (ORDER BY ord) AS rn FROM (
				SELECT ord FROM be_outbox WHERE stream = $1 AND partition = $2 AND seq IS NULL ORDER BY ord LIMIT $3
			) p
		)
		UPDATE be_outbox o SET seq = $4 + picked.rn, epoch_generation = $5, epoch_timeline = $6
		FROM picked WHERE o.ord = picked.ord""", "('s', 0, 500, 0, 1, 1)"),
    ("outbox_unpublished", "outbox", OUTBOX, dict(seq="g", ep="1"), 600,
     """SELECT ord, event_id::text, type, occurred_at, record_id, version, projection,
		coalesce(legal_entity, ''), subjects, coalesce(causation::text, ''), hops, trace, payload, digest, seq,
		epoch_generation, epoch_timeline
		FROM be_outbox WHERE stream = $1 AND partition = $2 AND seq IS NOT NULL AND published_at IS NULL
		ORDER BY epoch_generation, epoch_timeline, seq LIMIT $3""", "('s', 0, 500)"),
    ("work_claim", "work", WORK, {}, 20,
     """WITH expired AS (
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
			RETURNING w.id, w.job, w.kind, w.epoch, w.claim_db_generation, w.claim_db_timeline, w.attempts,
				w.max_attempts, w.effect_class, w.operation_id, w.outcome_unknown, w.args, w.progress,
				coalesce(w.slot, ''), w.call_results""", "('{bulk,other}', 'h', 30)"),
    ("audit_number", "audit", AUDIT, dict(seq="NULL", ep="NULL"), 600,
     """WITH picked AS (
				SELECT ord, row_number() OVER (ORDER BY ord) AS rn FROM (
					SELECT ord FROM be_audit_log WHERE seq IS NULL ORDER BY ord LIMIT $1) p)
			UPDATE be_audit_log l SET seq = $2 + picked.rn, epoch_generation = $3, epoch_timeline = $4
			FROM picked WHERE l.ord = picked.ord""", "(500, 0, 1, 1)"),
    ("audit_transfer", "audit", AUDIT, dict(seq="g", ep="1"), 600,
     """SELECT id::text, seq, epoch_generation, epoch_timeline, digest, record
			FROM be_audit_log WHERE transfer_state = 'pending' AND seq IS NOT NULL AND record IS NOT NULL
			ORDER BY ord LIMIT $1""", "(500)"),
]
TABLE = {"outbox": "be_outbox", "work": "be_work_item", "audit": "be_audit_log"}
for name, kind, ins, kw, small, stmt, args in CASES:
    out.append(f"\\echo ===== {name}: {small} waiting")
    out.append(f"TRUNCATE {TABLE[kind]};")
    out.append(ins.format(a=1, b=small, **kw))
    if analyzed:
        out.append(f"ANALYZE {TABLE[kind]};")
    out.append(f"PREPARE {name} AS {stmt};")
    for _ in range(8):
        out.append(f"BEGIN; EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"BEGIN; EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"\\echo ===== {name}: 20000 waiting")
    out.append(ins.format(a=small + 1, b=20000, **kw))
    if analyzed:
        out.append(f"ANALYZE {TABLE[kind]};")
    for _ in range(3):
        out.append(f"BEGIN; EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"BEGIN; EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE {name}{args}; ROLLBACK;")
    out.append(f"DEALLOCATE {name};")
out.append("DROP SCHEMA t3_probe CASCADE;")
print("\n".join(out))
