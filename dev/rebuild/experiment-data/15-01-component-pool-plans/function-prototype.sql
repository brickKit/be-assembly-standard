\set ON_ERROR_STOP on
\pset pager off
DROP SCHEMA IF EXISTS t3_fn CASCADE;
CREATE SCHEMA t3_fn;
SET search_path = t3_fn;
-- Document number series (protocol 14, "document numbers"): one row per series scope; the next number is taken in
-- the issuing transaction, so a rollback gives it back and continuous series leave no gaps.
CREATE TABLE be_doc_series (
    series      text PRIMARY KEY,
    last_number bigint NOT NULL CHECK (last_number >= 0),
    gapless     boolean NOT NULL
);

-- Events (chapter 06): the deployment recovery generation and the database epoch, the outbox with its per-partition
-- counters and epoch history, and the consumer's inbox and dead letters. Every SDK applies this same file.
CREATE TABLE be_recovery_generation (
    single     boolean PRIMARY KEY DEFAULT true CHECK (single),
    generation bigint NOT NULL CHECK (generation >= 1)
);
INSERT INTO be_recovery_generation (generation) VALUES (1);

-- (deployment recovery generation, current write timeline); fails on a standby, which refuses numbering (P6.8)
CREATE FUNCTION be_current_db_epoch(OUT generation bigint, OUT timeline bigint) LANGUAGE sql VOLATILE AS $$
    SELECT g.generation, ('x' || substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::bigint
    FROM be_recovery_generation g
$$;

CREATE TABLE be_outbox (
    ord              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id         uuid NOT NULL UNIQUE,
    stream           text NOT NULL,
    partition        integer NOT NULL CHECK (partition >= 0),
    type             text NOT NULL,
    occurred_at      timestamptz NOT NULL,
    record_id        text NOT NULL,
    version          bigint NOT NULL,
    projection       text NOT NULL CHECK (projection IN ('full', 'partial', 'delete')),
    legal_entity     text,
    subjects         jsonb,
    causation        uuid,
    hops             integer NOT NULL CHECK (hops >= 0),
    trace            jsonb,
    payload          bytea NOT NULL,
    claim            boolean NOT NULL DEFAULT false,
    digest           text NOT NULL,
    seq              bigint,
    epoch_generation bigint,
    epoch_timeline   bigint,
    published_at     timestamptz,
    CHECK ((seq IS NULL) = (epoch_generation IS NULL) AND (seq IS NULL) = (epoch_timeline IS NULL))
);
CREATE INDEX be_outbox_unnumbered ON be_outbox (stream, partition, ord) WHERE seq IS NULL;
CREATE UNIQUE INDEX be_outbox_position ON be_outbox (stream, partition, epoch_generation, epoch_timeline, seq)
    WHERE seq IS NOT NULL;
CREATE INDEX be_outbox_unpublished ON be_outbox (stream, partition, seq) WHERE seq IS NOT NULL AND published_at IS NULL;
CREATE INDEX be_outbox_published ON be_outbox (published_at) WHERE published_at IS NOT NULL;

CREATE TABLE be_outbox_partition (
    stream           text NOT NULL,
    partition        integer NOT NULL,
    epoch_generation bigint,
    epoch_timeline   bigint,
    last_seq         bigint NOT NULL DEFAULT 0,
    lease_owner      text,
    lease_until      timestamptz,
    PRIMARY KEY (stream, partition)
);

CREATE TABLE be_epoch_history (
    stream          text NOT NULL,
    partition       integer NOT NULL,
    old_generation  bigint NOT NULL,
    old_timeline    bigint NOT NULL,
    fork_seq        bigint NOT NULL,
    new_generation  bigint NOT NULL,
    new_timeline    bigint NOT NULL,
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (stream, partition, new_generation, new_timeline)
);

-- deduplication by identity is never partitioned (protocol 14)
CREATE TABLE be_inbox (
    subscription text NOT NULL,
    event_id     uuid NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (subscription, event_id)
);

CREATE TABLE be_dead_letter (
    subscription text NOT NULL,
    event_id     text NOT NULL,
    type         text NOT NULL,
    headers      jsonb NOT NULL,
    payload      bytea NOT NULL,
    error        text NOT NULL,
    attempts     integer NOT NULL,
    recorded_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (subscription, event_id)
);

-- Background work items (chapter 07, protocol 01 of the assembly project).
CREATE TABLE be_work_item (
    id                  text PRIMARY KEY,
    job                 text NOT NULL,
    kind                text NOT NULL CHECK (kind IN ('queue', 'cron', 'singleton')),
    state               text NOT NULL CHECK (state IN ('pending', 'running', 'retry_wait', 'done', 'dead', 'paused', 'resolved')),
    epoch               bigint NOT NULL DEFAULT 0,
    claim_db_generation bigint,
    claim_db_timeline   bigint,
    holder              text,
    lease_until         timestamptz,
    attempts            integer NOT NULL DEFAULT 0,
    max_attempts        integer NOT NULL CHECK (max_attempts >= 1),
    run_at              timestamptz NOT NULL DEFAULT now(),
    effect_class        text NOT NULL CHECK (effect_class IN ('local', 'idempotent_external', 'non_idempotent_external', 'emit_only')),
    operation_id        text NOT NULL,
    call_results        jsonb NOT NULL DEFAULT '{}',
    waiting_since       timestamptz,
    outcome_unknown     boolean NOT NULL DEFAULT false,
    pause_reason        text CHECK (pause_reason IN ('outcome_unknown', 'backlog_exceeded', 'business_hold')),
    args                jsonb,
    progress            jsonb,
    result              jsonb,
    last_error          text,
    initiator           jsonb,
    trace               jsonb,
    slot                text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    finished_at         timestamptz,
    CHECK ((state = 'paused') = (pause_reason IS NOT NULL))
);
CREATE INDEX be_work_item_due ON be_work_item (job, run_at) WHERE state IN ('pending', 'retry_wait');
CREATE INDEX be_work_item_lease ON be_work_item (job, lease_until) WHERE state = 'running';
CREATE INDEX be_work_item_finished ON be_work_item (finished_at) WHERE state IN ('done', 'resolved');

CREATE TABLE be_cron_watermark (
    job          text PRIMARY KEY,
    watermark_at timestamptz NOT NULL,
    last_slot    text
);

-- The local audit table (chapter 08, P8.19-P8.23; protocol 03 of the assembly project): append-only, numbered after
-- commit under its own counter's lock, transferred with receipts.
CREATE TABLE be_audit_log (
    ord              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id               uuid NOT NULL UNIQUE,
    seq              bigint,
    epoch_generation bigint,
    epoch_timeline   bigint,
    occurred_at      timestamptz NOT NULL,
    category         text NOT NULL CHECK (category IN ('business_change', 'security_change', 'sensitive_read',
                                                       'delegated', 'security_denial', 'work_disposition')),
    operation        text NOT NULL,
    outcome          text NOT NULL CHECK (outcome IN ('succeeded', 'denied', 'failed')),
    reason           text,
    actor            jsonb,
    represented      jsonb,
    target           jsonb,
    changes          jsonb,
    request          jsonb,
    summary          jsonb,
    digest           text NOT NULL,
    transfer_state   text NOT NULL DEFAULT 'pending' CHECK (transfer_state IN ('pending', 'received', 'conflict')),
    receipt_epoch    text,
    receipt_seq      bigint,
    receipt_chain    text,
    received_at      timestamptz,
    CHECK ((seq IS NULL) = (epoch_generation IS NULL) AND (seq IS NULL) = (epoch_timeline IS NULL))
);
CREATE INDEX be_audit_log_unnumbered ON be_audit_log (ord) WHERE seq IS NULL;
CREATE UNIQUE INDEX be_audit_log_position ON be_audit_log (epoch_generation, epoch_timeline, seq) WHERE seq IS NOT NULL;
CREATE INDEX be_audit_log_pending ON be_audit_log (ord) WHERE transfer_state = 'pending' AND seq IS NOT NULL;

CREATE TABLE be_audit_counter (
    single           boolean PRIMARY KEY DEFAULT true CHECK (single),
    epoch_generation bigint,
    epoch_timeline   bigint,
    last_seq         bigint NOT NULL DEFAULT 0
);
INSERT INTO be_audit_counter (single) VALUES (true);

-- denial details per principal, reason and minute (P8.23): within the budget each denial is its own row; past it
-- the window only counts here, and once the minute is over one summary row with the count is appended
CREATE TABLE be_audit_denial_budget (
    principal  text NOT NULL,
    reason     text NOT NULL,
    minute     timestamptz NOT NULL,
    detailed   integer NOT NULL DEFAULT 0,
    overflow   integer NOT NULL DEFAULT 0,
    first_at   timestamptz,
    last_at    timestamptz,
    summarized boolean NOT NULL DEFAULT false,
    PRIMARY KEY (principal, reason, minute)
);
CREATE INDEX be_audit_denial_unsummarized ON be_audit_denial_budget (minute) WHERE overflow > 0 AND NOT summarized;

-- Projections (chapter 09, P9.10-P9.12; protocol 02 of the assembly project): local copies of other components'
-- records with their version and state, and per projection the adopted source and alignment generation.
CREATE TABLE be_projection (
    projection   text NOT NULL,
    record_id    text NOT NULL,
    version      bigint NOT NULL CHECK (version >= 0),
    state        text NOT NULL CHECK (state IN ('complete', 'incomplete', 'tombstone')),
    need_version bigint,
    impl         text,
    epoch        text,
    data         jsonb,
    aligned_gen  bigint,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (projection, record_id),
    CHECK ((state = 'incomplete') = (need_version IS NOT NULL))
);
CREATE INDEX be_projection_incomplete ON be_projection (projection) WHERE state = 'incomplete';

CREATE TABLE be_projection_source (
    projection text PRIMARY KEY,
    impl       text,
    epoch      text,
    align_gen  bigint NOT NULL DEFAULT 0,
    status     text NOT NULL DEFAULT 'aligning' CHECK (status IN ('aligning', 'aligned', 'stalled', 'blocked')),
    aligned_at timestamptz
);

-- Monthly partitions (chapter 05, P5.21-P5.24; protocol 14, "partition maintenance at run time"). A component's
-- migration declares a range-partitioned table with be_declare_monthly_partitions; be_maintain_partitions, run by
-- the SDK's maintenance job as the runtime role, creates the months ahead as the owner and does nothing else.
CREATE TABLE be_partition_plan (
    table_name   text PRIMARY KEY,
    key_column   text NOT NULL,
    key_type     text NOT NULL CHECK (key_type IN ('date', 'timestamp with time zone')),
    months_ahead integer NOT NULL CHECK (months_ahead BETWEEN 1 AND 24),
    declared_at  timestamptz NOT NULL DEFAULT now()
);

-- Only the owner (the migrate entry) writes the plan; the runtime role's default table grants do not reach it.
CREATE FUNCTION be_partition_plan_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_user <> (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid = TG_RELID) THEN
        RAISE EXCEPTION 'be_partition_plan is written by migrations only' USING ERRCODE = '42501';
    END IF;
    RETURN NULL;
END
$$;

CREATE TRIGGER be_partition_plan_guard BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON be_partition_plan
    FOR EACH STATEMENT EXECUTE FUNCTION be_partition_plan_guard();

-- The maintenance function runs as its owner, in UTC, with the search path pinned to this schema (pg_temp last).
CREATE FUNCTION be_maintain_partitions() RETURNS SETOF text LANGUAGE plpgsql SECURITY DEFINER SET timezone = 'UTC' AS $body$
DECLARE
    p      record;
    m      integer;
    lo     date;
    hi     date;
    child  text;
    lo_text text;
    hi_text text;
    want   text;
    have   text;
    parent text;
    month0 date := date_trunc('month', now())::date;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('be_partitions:' || current_schema(), 0));
    FOR p IN SELECT table_name, key_type, months_ahead FROM be_partition_plan ORDER BY table_name LOOP
        IF to_regclass(quote_ident(p.table_name)) IS NULL THEN
            RAISE EXCEPTION 'the declared table % no longer exists: undeclare it with be_undeclare_monthly_partitions in the migration that drops or renames it',
                p.table_name USING ERRCODE = '42P01';
        END IF;
        FOR m IN 0..p.months_ahead LOOP
            lo := (month0 + make_interval(months => m))::date;
            hi := (lo + interval '1 month')::date;
            child := p.table_name || '_p' || to_char(lo, 'YYYYMM');
            -- the bounds as PostgreSQL prints them for the key's type, to compare with an existing partition
            EXECUTE format('SELECT %L::%s::text, %L::%s::text', lo, p.key_type, hi, p.key_type) INTO lo_text, hi_text;
            want := format('FOR VALUES FROM (%L) TO (%L)', lo_text, hi_text);
            SELECT pg_get_expr(c.relpartbound, c.oid), i.inhparent::regclass::text INTO have, parent
                FROM pg_class c LEFT JOIN pg_inherits i ON i.inhrelid = c.oid
                WHERE c.relname = child AND c.relnamespace = current_schema()::regnamespace;
            IF FOUND THEN
                IF parent IS DISTINCT FROM p.table_name OR have IS DISTINCT FROM want THEN
                    RAISE EXCEPTION 'partition % exists but is not % of %: %', child, want, p.table_name, coalesce(have, 'detached')
                        USING ERRCODE = '42P17';
                END IF;
                CONTINUE;
            END IF;
            EXECUTE format('CREATE TABLE %I (LIKE %I INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED INCLUDING STORAGE INCLUDING COMMENTS)',
                child, p.table_name);
            EXECUTE format('ALTER TABLE %I ATTACH PARTITION %I %s', p.table_name, child, want);
            RETURN NEXT child;
        END LOOP;
    END LOOP;
END
$body$;

DO $do$
BEGIN
    EXECUTE format('ALTER FUNCTION be_maintain_partitions() SET search_path = %I, pg_temp', current_schema());
END
$do$;

-- Declaring checks the table (range-partitioned on one date or timestamptz column in this schema), records the plan
-- and creates the current month and the months ahead. It runs in the component's migration, as the owner.
CREATE FUNCTION be_declare_monthly_partitions(p_table text, p_months_ahead integer DEFAULT 3) RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
    v_column text;
    v_type   text;
BEGIN
    SELECT a.attname, format_type(a.atttypid, a.atttypmod) INTO v_column, v_type
        FROM pg_partitioned_table pt
        JOIN pg_class c ON c.oid = pt.partrelid
        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = pt.partattrs[0]
        WHERE c.relname = p_table AND c.relnamespace = current_schema()::regnamespace
          AND pt.partstrat = 'r' AND pt.partnatts = 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION '% is not a table of this schema partitioned by range on one column', p_table USING ERRCODE = '42P17';
    END IF;
    IF octet_length(p_table) > 55 THEN
        RAISE EXCEPTION 'the name % is longer than 55 bytes: its partitions (<name>_pYYYYMM) would be truncated', p_table
            USING ERRCODE = '42622';
    END IF;
    IF v_type NOT IN ('date', 'timestamp with time zone') THEN
        RAISE EXCEPTION 'the partition key %.% is %, not date or timestamptz', p_table, v_column, v_type USING ERRCODE = '42P17';
    END IF;
    INSERT INTO be_partition_plan (table_name, key_column, key_type, months_ahead)
        VALUES (p_table, v_column, v_type, p_months_ahead)
        ON CONFLICT (table_name) DO UPDATE SET months_ahead = excluded.months_ahead;
    RETURN QUERY SELECT * FROM be_maintain_partitions();
END
$$;

-- Undeclaring belongs to the migration that drops or renames a declared table; existing partitions stay as they are.
CREATE FUNCTION be_undeclare_monthly_partitions(p_table text) RETURNS void LANGUAGE sql AS $$
    DELETE FROM be_partition_plan WHERE table_name = p_table;
$$;

-- Command idempotency keys (chapter 04, P4.21-P4.25): one row per (principal, key), claimed by an atomic insert in
-- the command's transaction together with its writes and its outcome. Not partitioned: it deduplicates by identity.
CREATE TABLE be_idempotency (
    principal   text NOT NULL,
    key         text NOT NULL,
    fingerprint text NOT NULL,
    operation   text NOT NULL,
    status      integer NOT NULL,
    result      jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL,
    PRIMARY KEY (principal, key)
);
CREATE INDEX be_idempotency_expiry ON be_idempotency (expires_at);

-- P7.22: a claim takes an expired lease first, then the earliest due item, each through an index in its own order, so
-- a backlog does not slow a claim. The due index orders by run_at alone (a component's table holds only its own
-- jobs); it replaces the (job, run_at) index, with which a claim over several jobs fetched and sorted the whole
-- backlog (20 000 items: 3-8 ms a claim, against 0.1-0.2 ms).
CREATE INDEX be_work_item_due_at ON be_work_item (run_at) WHERE state IN ('pending', 'retry_wait');
DROP INDEX be_work_item_due;

-- P8.20, P8.21: a row keeps its record's canonical bytes, written with the row and sent unchanged, so the audit
-- component checks the digest against exactly the bytes it was computed over (D76). Rebuilding the record from the
-- columns at transfer gave other bytes (nulls, the database's timestamp format, key order). Rows written before this
-- migration have none and are not transferred (pre-release data only).
ALTER TABLE be_audit_log ADD COLUMN record bytea;
DROP INDEX be_audit_log_pending;
CREATE INDEX be_audit_log_pending ON be_audit_log (ord) WHERE transfer_state = 'pending' AND seq IS NOT NULL AND record IS NOT NULL;

-- P6.35: the forwarder reads a partition's unpublished rows in position order (epoch, then sequence); the index on
-- (stream, partition, seq) did not give that order, so every batch either walked past the published rows kept for
-- the redelivery retention (P6.12) along the position index or fetched and sorted every unpublished row (20 000
-- published rows ahead: 3.4 ms a batch of 500, against 0.6 ms along this index; 2026-11-02).
CREATE INDEX be_outbox_unpublished_in_order ON be_outbox (stream, partition, epoch_generation, epoch_timeline, seq)
    WHERE seq IS NOT NULL AND published_at IS NULL;
DROP INDEX be_outbox_unpublished;
ALTER INDEX be_outbox_unpublished_in_order RENAME TO be_outbox_unpublished;

-- P5.33: the SDK's statements keep cached generic plans; one settled while a queue table was small stays until the
-- table is next analyzed, and autovacuum analyzes up to a naptime (60 s by default) after a backlog arrived. Every
-- process that opens the database calls this every 2 seconds: it analyzes the SDK's queue tables that changed by at
-- least 1000 rows and at least their estimated size since their last analyze, if that was over 30 seconds ago;
-- the analyze invalidates the cached plans. It runs as the owner (ANALYZE needs it); one caller at a time.
CREATE FUNCTION be_analyze_stale() RETURNS SETOF text LANGUAGE plpgsql SECURITY DEFINER AS $body$
DECLARE
    t        text;
    changed  bigint;
    estimate real;
    last     timestamptz;
BEGIN
    IF NOT pg_try_advisory_xact_lock(hashtextextended('be_analyze:' || current_schema(), 0)) THEN
        RETURN;
    END IF;
    FOREACH t IN ARRAY ARRAY['be_outbox', 'be_work_item', 'be_audit_log'] LOOP
        SELECT s.n_mod_since_analyze, c.reltuples, greatest(s.last_analyze, s.last_autoanalyze)
            INTO changed, estimate, last
            FROM pg_stat_all_tables s JOIN pg_class c ON c.oid = s.relid
            WHERE s.relid = format('%I.%I', current_schema(), t)::regclass;
        IF changed >= greatest(1000, estimate) AND (last IS NULL OR last < now() - interval '30 seconds') THEN
            EXECUTE format('ANALYZE %I.%I', current_schema(), t);
            RETURN NEXT t;
        END IF;
    END LOOP;
END
$body$;

DO $do$
BEGIN
    EXECUTE format('ALTER FUNCTION be_analyze_stale() SET search_path = %I, pg_temp', current_schema());
END
$do$;

ALTER TABLE be_work_item SET (autovacuum_enabled = false);
INSERT INTO be_work_item (id, job, kind, state, max_attempts, effect_class, operation_id, args, run_at)
  SELECT gen_random_uuid()::text, CASE WHEN g % 2 = 0 THEN 'bulk' ELSE 'other' END, 'queue', 'pending', 3, 'local',
  gen_random_uuid()::text, '{}'::jsonb, now() - g * interval '1 ms' FROM generate_series(1, 20) g;
\echo == never analyzed, 20 items: the function does nothing (under 1000 changed)
SELECT pg_stat_force_next_flush(); SELECT be_analyze_stale();
PREPARE c(text[], text, float8) AS WITH expired AS (
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
				coalesce(w.slot, ''), w.call_results;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
INSERT INTO be_work_item (id, job, kind, state, max_attempts, effect_class, operation_id, args, run_at)
  SELECT gen_random_uuid()::text, CASE WHEN g % 2 = 0 THEN 'bulk' ELSE 'other' END, 'queue', 'pending', 3, 'local',
  gen_random_uuid()::text, '{}'::jsonb, now() - g * interval '1 ms' FROM generate_series(21, 20000) g;
\echo == 20 000 items, before the function
BEGIN; EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON, TIMING OFF) EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
SELECT pg_stat_force_next_flush();
\echo == the function
SELECT be_analyze_stale();
\echo == after the function
BEGIN; EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON, TIMING OFF) EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
BEGIN; EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
\echo == after six more executions (the plan settled again)
BEGIN; EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON, TIMING OFF) EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;
\echo == called again at once: nothing (analyzed under 30 s ago, nothing changed)
SELECT pg_stat_force_next_flush(); SELECT be_analyze_stale();
\echo == a temporary table of the same name changes nothing
CREATE TEMP TABLE be_work_item (x int); SELECT be_analyze_stale();
DROP SCHEMA t3_fn CASCADE;
