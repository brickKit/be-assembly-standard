"""Writes bench-setup.sql: schema t3_bench with every SDK migration, 20 000 due work items and 20 000 published plus
600 unpublished outbox rows, analyzed (the steady state); the bench then claims and reads in rolled-back transactions."""
import glob
import os

here = os.path.dirname(os.path.abspath(__file__))
out = ["\\set ON_ERROR_STOP on", "DROP SCHEMA IF EXISTS t3_bench CASCADE;", "CREATE SCHEMA t3_bench;", "SET search_path = t3_bench;"]
for m in sorted(glob.glob(os.path.join(here, "../../../../tools/be-protocol/migrations/*.up.sql"))):
    out.append(open(m).read())
out.append("""INSERT INTO be_work_item (id, job, kind, state, max_attempts, effect_class, operation_id, args, run_at)
  SELECT gen_random_uuid()::text, CASE WHEN g % 2 = 0 THEN 'bulk' ELSE 'other' END, 'queue', 'pending', 3, 'local',
  gen_random_uuid()::text, '{}'::jsonb, now() - g * interval '1 ms' FROM generate_series(1, 20000) g;
INSERT INTO be_outbox (event_id, stream, partition, type, occurred_at, record_id, version, projection, hops,
  payload, digest, seq, epoch_generation, epoch_timeline, published_at)
  SELECT gen_random_uuid(), 's', 0, 't.v1', now(), g::text, 1, 'full', 0, '\\x7b7d', 'd', g, 1, 1,
  CASE WHEN g <= 20000 THEN now() END FROM generate_series(1, 20600) g;
ANALYZE be_work_item; ANALYZE be_outbox;""")
print("\n".join(out))
