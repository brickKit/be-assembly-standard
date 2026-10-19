-- Two copies of a work-item table with the same rows: q_or keeps the indexes the OR claim used, q_split the ones the
-- split claim uses. :n due items spread over three jobs, plus 200 finished ones; no expired lease.
DROP SCHEMA IF EXISTS q_or CASCADE; DROP SCHEMA IF EXISTS q_split CASCADE;
CREATE SCHEMA q_or; CREATE SCHEMA q_split;
CREATE TABLE q_or.item (id text PRIMARY KEY, job text NOT NULL, state text NOT NULL, run_at timestamptz NOT NULL,
                        lease_until timestamptz, pad text);
INSERT INTO q_or.item SELECT 'w' || g, 'job' || (g % 3), 'pending', now() - make_interval(secs => g), NULL, repeat('x', 200)
  FROM generate_series(1, :n) g;
INSERT INTO q_or.item SELECT 'd' || g, 'job' || (g % 3), 'done', now() - interval '1 day', NULL, repeat('x', 200)
  FROM generate_series(1, 200) g;
CREATE TABLE q_split.item (LIKE q_or.item INCLUDING ALL);
INSERT INTO q_split.item SELECT * FROM q_or.item;
CREATE INDEX ON q_or.item (job, run_at) WHERE state IN ('pending', 'retry_wait');
CREATE INDEX ON q_or.item (job, lease_until) WHERE state = 'running';
CREATE INDEX ON q_split.item (run_at) WHERE state IN ('pending', 'retry_wait');
CREATE INDEX ON q_split.item (job, lease_until) WHERE state = 'running';
ANALYZE q_or.item; ANALYZE q_split.item;
