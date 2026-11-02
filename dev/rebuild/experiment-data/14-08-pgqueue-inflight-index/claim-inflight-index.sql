-- With a candidate index be_bus_delivery_in_flight (durable, seq) WHERE in_flight. EXPLAIN ANALYZE of each claim: mirrors be-sdk-go TestABacklogDoesNotSlowEachClaim (v3.0.0-alpha.44's test, own fresh bus) in psql, for both plan
-- cache modes; the claim is v3.0.0-alpha.43's Transport.claim. psql -X -f claim-like-the-test.sql
\set ON_ERROR_STOP on
\pset pager off
\timing on
-- ===== plan_cache_mode = auto: a fresh schema from migrations-bus, never analyzed; as TestABacklogDoesNotSlowEachClaim:
-- subscription "small" with 20 deliveries, 15 claims; then "large" with 20 000, 15 claims; every claim EXPLAIN ANALYZE
DROP SCHEMA IF EXISTS claim_probe CASCADE;
CREATE SCHEMA claim_probe;
SET search_path = claim_probe;
SET plan_cache_mode = auto;
-- The PostgreSQL queue transport (chapter 06, P6.16-P6.23), in the bus database's own schema. Messages are read in
-- (transaction ID, sequence) order and only below pg_snapshot_xmin: every transaction under it has ended and no new
-- one can get a smaller ID, so a reader never skips a row that commits later.
CREATE TABLE be_bus_message (
    seq          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    xid          xid8 NOT NULL DEFAULT pg_current_xact_id(),
    msg_id       text,
    subject      text NOT NULL,
    headers      jsonb NOT NULL,
    data         bytea NOT NULL,
    published_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX be_bus_message_id ON be_bus_message (msg_id) WHERE msg_id IS NOT NULL;
CREATE INDEX be_bus_message_order ON be_bus_message (xid, seq);
CREATE INDEX be_bus_message_age ON be_bus_message (published_at);

CREATE TABLE be_bus_stream (
    name       text PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE be_bus_subscription (
    durable     text PRIMARY KEY,
    streams     text[] NOT NULL,
    filters     text[] NOT NULL,
    max_deliver integer NOT NULL,
    ack_wait_ms integer NOT NULL,
    backoff_ms  integer[] NOT NULL,
    pos_xid     xid8 NOT NULL DEFAULT '0',
    pos_seq     bigint NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- one row per message a subscription still has to settle; deleted when acknowledged or given up
CREATE TABLE be_bus_delivery (
    durable     text NOT NULL REFERENCES be_bus_subscription ON DELETE CASCADE,
    seq         bigint NOT NULL,
    attempts    integer NOT NULL DEFAULT 0,
    in_flight   boolean NOT NULL DEFAULT false,
    not_before  timestamptz NOT NULL DEFAULT now(),
    lease_until timestamptz,
    lease_token uuid,
    PRIMARY KEY (durable, seq)
);
CREATE INDEX be_bus_delivery_due ON be_bus_delivery (durable, not_before) WHERE NOT in_flight;
CREATE INDEX be_bus_delivery_lease ON be_bus_delivery (durable, lease_until) WHERE in_flight;
-- A subscription takes its due deliveries in position order (P6.23, P6.28). Ordered by not_before, the index let the
-- planner fetch and sort every waiting row when the statistics lagged behind a sudden backlog (about 10 ms a claim
-- with 20 000 waiting, 0.1 ms once analysed); ordered by seq, the first due delivery is near the start of the index
-- whatever the statistics say.
DROP INDEX be_bus_delivery_due;
CREATE INDEX be_bus_delivery_ready ON be_bus_delivery (durable, seq) WHERE NOT in_flight;
-- candidate: the expired path in position order along the in-flight rows only
CREATE INDEX be_bus_delivery_in_flight ON be_bus_delivery (durable, seq) WHERE in_flight;
PREPARE claim(text, uuid, double precision, int) AS
  WITH ready AS (SELECT seq FROM be_bus_delivery WHERE durable = $1 AND NOT in_flight
        AND not_before <= clock_timestamp() ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED),
      expired AS (SELECT seq FROM be_bus_delivery WHERE durable = $1 AND in_flight AND lease_until < clock_timestamp()
        AND attempts < $4 ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED),
      due AS (SELECT min(seq) AS seq FROM (SELECT seq FROM ready UNION ALL SELECT seq FROM expired) c),
    claimed AS (UPDATE be_bus_delivery d SET in_flight = true, attempts = d.attempts + 1, lease_token = $2,
      lease_until = clock_timestamp() + make_interval(secs => $3)
      WHERE d.durable = $1 AND d.seq = (SELECT seq FROM due) RETURNING d.seq, d.attempts)
  SELECT c.seq, c.attempts, m.subject, m.headers, m.data FROM claimed c
    LEFT JOIN be_bus_message m ON m.seq = c.seq;
INSERT INTO be_bus_subscription (durable, streams, filters, max_deliver, ack_wait_ms, backoff_ms) VALUES ('small', '{x}', '{}', 3, 30000, '{1000}');
WITH m AS (INSERT INTO be_bus_message (subject, headers, data) SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20) RETURNING seq)
  INSERT INTO be_bus_delivery (durable, seq) SELECT 'small', seq FROM m;
\echo '== auto small claim 1'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 2'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 3'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 4'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 5'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 6'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 7'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 8'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 9'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 10'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 11'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 12'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 13'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 14'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== auto small claim 15'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
INSERT INTO be_bus_subscription (durable, streams, filters, max_deliver, ack_wait_ms, backoff_ms) VALUES ('large', '{x}', '{}', 3, 30000, '{1000}');
WITH m AS (INSERT INTO be_bus_message (subject, headers, data) SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20000) RETURNING seq)
  INSERT INTO be_bus_delivery (durable, seq) SELECT 'large', seq FROM m;
\echo '== auto large claim 1'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 2'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 3'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 4'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 5'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 6'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 7'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 8'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 9'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 10'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 11'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 12'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 13'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 14'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== auto large claim 15'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
DEALLOCATE claim;
-- ===== plan_cache_mode = force_custom_plan: a fresh schema from migrations-bus, never analyzed; as TestABacklogDoesNotSlowEachClaim:
-- subscription "small" with 20 deliveries, 15 claims; then "large" with 20 000, 15 claims; every claim EXPLAIN ANALYZE
DROP SCHEMA IF EXISTS claim_probe CASCADE;
CREATE SCHEMA claim_probe;
SET search_path = claim_probe;
SET plan_cache_mode = force_custom_plan;
-- The PostgreSQL queue transport (chapter 06, P6.16-P6.23), in the bus database's own schema. Messages are read in
-- (transaction ID, sequence) order and only below pg_snapshot_xmin: every transaction under it has ended and no new
-- one can get a smaller ID, so a reader never skips a row that commits later.
CREATE TABLE be_bus_message (
    seq          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    xid          xid8 NOT NULL DEFAULT pg_current_xact_id(),
    msg_id       text,
    subject      text NOT NULL,
    headers      jsonb NOT NULL,
    data         bytea NOT NULL,
    published_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX be_bus_message_id ON be_bus_message (msg_id) WHERE msg_id IS NOT NULL;
CREATE INDEX be_bus_message_order ON be_bus_message (xid, seq);
CREATE INDEX be_bus_message_age ON be_bus_message (published_at);

CREATE TABLE be_bus_stream (
    name       text PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE be_bus_subscription (
    durable     text PRIMARY KEY,
    streams     text[] NOT NULL,
    filters     text[] NOT NULL,
    max_deliver integer NOT NULL,
    ack_wait_ms integer NOT NULL,
    backoff_ms  integer[] NOT NULL,
    pos_xid     xid8 NOT NULL DEFAULT '0',
    pos_seq     bigint NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- one row per message a subscription still has to settle; deleted when acknowledged or given up
CREATE TABLE be_bus_delivery (
    durable     text NOT NULL REFERENCES be_bus_subscription ON DELETE CASCADE,
    seq         bigint NOT NULL,
    attempts    integer NOT NULL DEFAULT 0,
    in_flight   boolean NOT NULL DEFAULT false,
    not_before  timestamptz NOT NULL DEFAULT now(),
    lease_until timestamptz,
    lease_token uuid,
    PRIMARY KEY (durable, seq)
);
CREATE INDEX be_bus_delivery_due ON be_bus_delivery (durable, not_before) WHERE NOT in_flight;
CREATE INDEX be_bus_delivery_lease ON be_bus_delivery (durable, lease_until) WHERE in_flight;
-- A subscription takes its due deliveries in position order (P6.23, P6.28). Ordered by not_before, the index let the
-- planner fetch and sort every waiting row when the statistics lagged behind a sudden backlog (about 10 ms a claim
-- with 20 000 waiting, 0.1 ms once analysed); ordered by seq, the first due delivery is near the start of the index
-- whatever the statistics say.
DROP INDEX be_bus_delivery_due;
CREATE INDEX be_bus_delivery_ready ON be_bus_delivery (durable, seq) WHERE NOT in_flight;
-- candidate: the expired path in position order along the in-flight rows only
CREATE INDEX be_bus_delivery_in_flight ON be_bus_delivery (durable, seq) WHERE in_flight;
PREPARE claim(text, uuid, double precision, int) AS
  WITH ready AS (SELECT seq FROM be_bus_delivery WHERE durable = $1 AND NOT in_flight
        AND not_before <= clock_timestamp() ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED),
      expired AS (SELECT seq FROM be_bus_delivery WHERE durable = $1 AND in_flight AND lease_until < clock_timestamp()
        AND attempts < $4 ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED),
      due AS (SELECT min(seq) AS seq FROM (SELECT seq FROM ready UNION ALL SELECT seq FROM expired) c),
    claimed AS (UPDATE be_bus_delivery d SET in_flight = true, attempts = d.attempts + 1, lease_token = $2,
      lease_until = clock_timestamp() + make_interval(secs => $3)
      WHERE d.durable = $1 AND d.seq = (SELECT seq FROM due) RETURNING d.seq, d.attempts)
  SELECT c.seq, c.attempts, m.subject, m.headers, m.data FROM claimed c
    LEFT JOIN be_bus_message m ON m.seq = c.seq;
INSERT INTO be_bus_subscription (durable, streams, filters, max_deliver, ack_wait_ms, backoff_ms) VALUES ('small', '{x}', '{}', 3, 30000, '{1000}');
WITH m AS (INSERT INTO be_bus_message (subject, headers, data) SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20) RETURNING seq)
  INSERT INTO be_bus_delivery (durable, seq) SELECT 'small', seq FROM m;
\echo '== force_custom_plan small claim 1'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 2'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 3'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 4'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 5'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 6'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 7'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 8'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 9'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 10'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 11'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 12'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 13'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 14'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan small claim 15'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('small', gen_random_uuid(), 30, 3);
INSERT INTO be_bus_subscription (durable, streams, filters, max_deliver, ack_wait_ms, backoff_ms) VALUES ('large', '{x}', '{}', 3, 30000, '{1000}');
WITH m AS (INSERT INTO be_bus_message (subject, headers, data) SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20000) RETURNING seq)
  INSERT INTO be_bus_delivery (durable, seq) SELECT 'large', seq FROM m;
\echo '== force_custom_plan large claim 1'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 2'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 3'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 4'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 5'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 6'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 7'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 8'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 9'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 10'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 11'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 12'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 13'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 14'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
\echo '== force_custom_plan large claim 15'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) EXECUTE claim('large', gen_random_uuid(), 30, 3);
DEALLOCATE claim;
SELECT version();
DROP SCHEMA claim_probe CASCADE;
