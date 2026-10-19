BEGIN;
WITH c AS (
  SELECT id FROM q_or.item WHERE job = ANY('{job0,job1,job2}') AND (
    (state IN ('pending', 'retry_wait') AND run_at <= now()) OR (state = 'running' AND lease_until <= now()))
  ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED)
UPDATE q_or.item i SET state = 'running', lease_until = now() + interval '30 seconds' FROM c WHERE i.id = c.id RETURNING i.id;
ROLLBACK;
