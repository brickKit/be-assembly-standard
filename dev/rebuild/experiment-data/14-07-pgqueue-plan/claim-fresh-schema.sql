-- Input of claim-fresh-schema.txt (complete output; 2026-11-02). The tables are copies of the shared test bus's
-- (LIKE ... INCLUDING ALL), which copies the two partial indexes under generated names: be_bus_delivery_durable_seq_idx
-- is be_bus_delivery_ready (WHERE NOT in_flight), be_bus_delivery_durable_lease_until_idx is be_bus_delivery_lease
-- (WHERE in_flight); see like-copy-indexes.txt. Never analyzed; 20 deliveries of another durable, then 20 000 of the
-- claimed one; no subscription table (the copy has no foreign key). Ran as: psql -X -U postgres -d be_sdk_test -q
\pset pager off
DROP SCHEMA IF EXISTS probe_b7c1 CASCADE; CREATE SCHEMA probe_b7c1;
CREATE TABLE probe_b7c1.be_bus_message (LIKE be_bus_test.be_bus_message INCLUDING ALL);
CREATE TABLE probe_b7c1.be_bus_delivery (LIKE be_bus_test.be_bus_delivery INCLUDING ALL);
SELECT 'reltuples before: ' || reltuples FROM pg_class WHERE oid = 'probe_b7c1.be_bus_delivery'::regclass;
INSERT INTO probe_b7c1.be_bus_message (subject, headers, data) SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20) ;
INSERT INTO probe_b7c1.be_bus_delivery (durable, seq) SELECT 'backlog_small', seq FROM probe_b7c1.be_bus_message;
WITH m AS (INSERT INTO probe_b7c1.be_bus_message (subject, headers, data) SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20000) RETURNING seq)
INSERT INTO probe_b7c1.be_bus_delivery (durable, seq) SELECT 'backlog_x', seq FROM m;
PREPARE c(text, uuid, double precision, int) AS WITH ready AS (SELECT seq FROM probe_b7c1.be_bus_delivery WHERE durable = $1 AND NOT in_flight AND not_before <= clock_timestamp() ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED), expired AS (SELECT seq FROM probe_b7c1.be_bus_delivery WHERE durable = $1 AND in_flight AND lease_until < clock_timestamp() AND attempts < $4 ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED), due AS (SELECT min(seq) AS seq FROM (SELECT seq FROM ready UNION ALL SELECT seq FROM expired) c), claimed AS (UPDATE probe_b7c1.be_bus_delivery d SET in_flight = true, attempts = d.attempts + 1, lease_token = $2, lease_until = clock_timestamp() + make_interval(secs => $3) WHERE d.durable = $1 AND d.seq = (SELECT seq FROM due) RETURNING d.seq, d.attempts) SELECT c.seq, c.attempts, m.subject FROM claimed c LEFT JOIN probe_b7c1.be_bus_message m ON m.seq = c.seq;
\echo '== execution 1'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 2'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 3'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 4'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 5'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 6'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 7'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 8'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 9'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
\echo '== execution 10'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE c('backlog_x', gen_random_uuid(), 30, 3);
DROP SCHEMA probe_b7c1 CASCADE;
