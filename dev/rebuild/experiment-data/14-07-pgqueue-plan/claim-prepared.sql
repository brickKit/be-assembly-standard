-- Input of claim-prepared.txt (2026-11-02, the shared test bus be_bus_test of database be_sdk_test, which held
-- what earlier test runs left). The saved output is FILTERED: the psql output went through
--   grep -E 'Time:|Scan|Sort|Seq|Execution|Limit|Hash|Bitmap|Filter' | cut -c1-140
-- so it has one "Time:" line per statement, in this order: 1 DELETE, 2 INSERT subscription, 3 ANALYZE, 4 INSERT of the
-- backlog, 5 PREPARE, 6-14 the nine EXECUTEs, then the plan lines of the tenth execution (EXPLAIN), 15 that EXPLAIN,
-- 16-17 the two DELETEs. Ran as: psql -U postgres -d be_sdk_test -q
\pset pager off
\timing on
DELETE FROM be_bus_test.be_bus_delivery WHERE durable LIKE 'backlog_%';
INSERT INTO be_bus_test.be_bus_subscription (durable, streams, filters, max_deliver, ack_wait_ms, backoff_ms) VALUES ('dbg_b7c1', '{x}', '{}', 3, 30000, '{1000}');
ANALYZE be_bus_test.be_bus_delivery;
WITH m AS (INSERT INTO be_bus_test.be_bus_message (subject, headers, data) SELECT 'be.dbg_b7c1.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20000) RETURNING seq)
INSERT INTO be_bus_test.be_bus_delivery (durable, seq) SELECT 'dbg_b7c1', seq FROM m;
PREPARE c(text, uuid, double precision, int) AS WITH ready AS (SELECT seq FROM be_bus_test.be_bus_delivery WHERE durable = $1 AND NOT in_flight AND not_before <= clock_timestamp() ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED), expired AS (SELECT seq FROM be_bus_test.be_bus_delivery WHERE durable = $1 AND in_flight AND lease_until < clock_timestamp() AND attempts < $4 ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED), due AS (SELECT min(seq) AS seq FROM (SELECT seq FROM ready UNION ALL SELECT seq FROM expired) c), claimed AS (UPDATE be_bus_test.be_bus_delivery d SET in_flight = true, attempts = d.attempts + 1, lease_token = $2, lease_until = clock_timestamp() + make_interval(secs => $3) WHERE d.durable = $1 AND d.seq = (SELECT seq FROM due) RETURNING d.seq, d.attempts) SELECT c.seq, c.attempts, m.subject FROM claimed c LEFT JOIN be_bus_test.be_bus_message m ON m.seq = c.seq;
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('dbg_b7c1', gen_random_uuid(), 30, 3);
DELETE FROM be_bus_test.be_bus_subscription WHERE durable = 'dbg_b7c1'; DELETE FROM be_bus_test.be_bus_message WHERE subject = 'be.dbg_b7c1.0.t.v1';
