BEGIN;
SET LOCAL search_path = idle;
WITH expired AS (
	SELECT id FROM be_work_item WHERE job = ANY('{q,c,s}') AND state = 'running' AND lease_until <= now()
	ORDER BY lease_until LIMIT 1 FOR UPDATE SKIP LOCKED),
due AS (
	SELECT id FROM be_work_item WHERE job = ANY('{q,c,s}') AND state IN ('pending', 'retry_wait') AND run_at <= now()
		AND NOT EXISTS (SELECT 1 FROM expired)
	ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED),
c AS (SELECT id FROM expired UNION ALL SELECT id FROM due)
UPDATE be_work_item w SET state = 'running', epoch = w.epoch + 1, attempts = w.attempts + 1, holder = 'x',
	lease_until = now() + make_interval(secs => 30), claim_db_generation = e.generation,
	claim_db_timeline = e.timeline
FROM c, be_current_db_epoch() e WHERE w.id = c.id RETURNING w.id;
ROLLBACK;
