BEGIN;
WITH expired AS (
  SELECT id FROM q_split.item WHERE job = ANY('{job0,job1,job2}') AND state = 'running' AND lease_until <= now()
  ORDER BY lease_until LIMIT 1 FOR UPDATE SKIP LOCKED),
due AS (
  SELECT id FROM q_split.item WHERE job = ANY('{job0,job1,job2}') AND state IN ('pending', 'retry_wait') AND run_at <= now()
    AND NOT EXISTS (SELECT 1 FROM expired)
  ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED),
c AS (SELECT id FROM expired UNION ALL SELECT id FROM due)
UPDATE q_split.item i SET state = 'running', lease_until = now() + interval '30 seconds' FROM c WHERE i.id = c.id RETURNING i.id;
ROLLBACK;
