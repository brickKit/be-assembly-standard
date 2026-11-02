BEGIN;
WITH expired AS (
				SELECT id FROM be_work_item WHERE job = ANY(:jobs) AND state = 'running' AND lease_until <= now()
				ORDER BY lease_until LIMIT 1 FOR UPDATE SKIP LOCKED),
			due AS (
				SELECT id FROM be_work_item WHERE job = ANY(:jobs) AND state IN ('pending', 'retry_wait') AND run_at <= now()
					AND NOT EXISTS (SELECT 1 FROM expired)
				ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED),
			c AS (SELECT id FROM expired UNION ALL SELECT id FROM due)
			UPDATE be_work_item w SET state = 'running', epoch = w.epoch + 1, attempts = w.attempts + 1, holder = :holder,
				lease_until = now() + make_interval(secs => :lease), claim_db_generation = e.generation,
				claim_db_timeline = e.timeline
			FROM c, be_current_db_epoch() e WHERE w.id = c.id
			RETURNING w.id, w.job, w.kind, w.epoch, w.claim_db_generation, w.claim_db_timeline, w.attempts,
				w.max_attempts, w.effect_class, w.operation_id, w.outcome_unknown, w.args, w.progress,
				coalesce(w.slot, ''), w.call_results;
ROLLBACK;
