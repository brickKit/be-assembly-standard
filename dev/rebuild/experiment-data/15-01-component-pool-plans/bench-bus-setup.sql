\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS t3_bus CASCADE;
CREATE SCHEMA t3_bus;
SET search_path = t3_bus;
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

-- A claim takes the first expired lease in position order (P6.28), along the in-flight rows only. Ordered by
-- lease_until, the index let the planner walk the subscription's whole backlog through the primary key and filter
-- it when the table had never been analysed (in_flight then estimated as true for half the rows): 1.7 ms a claim with
-- 20 000 waiting against 0.16 ms with 20, planned for its own parameters. Ordered by seq it gives the position order
-- the claim needs, and the planner takes it whatever the statistics say. The give-up sweep looks at the same
-- in-flight rows.
DROP INDEX be_bus_delivery_lease;
CREATE INDEX be_bus_delivery_in_flight ON be_bus_delivery (durable, seq) WHERE in_flight;

INSERT INTO be_bus_subscription (durable, streams, filters, max_deliver, ack_wait_ms, backoff_ms)
  VALUES ('d', '{x}', '{}', 3, 30000, '{1000}');
WITH m AS (INSERT INTO be_bus_message (subject, headers, data)
  SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20000) RETURNING seq)
INSERT INTO be_bus_delivery (durable, seq) SELECT 'd', seq FROM m;
ANALYZE be_bus_message; ANALYZE be_bus_delivery;
