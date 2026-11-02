BEGIN;
SELECT ord, event_id::text, type, occurred_at, record_id, version, projection,
		coalesce(legal_entity, ''), subjects, coalesce(causation::text, ''), hops, trace, payload, digest, seq,
		epoch_generation, epoch_timeline
		FROM be_outbox WHERE stream = :stream AND partition = :part AND seq IS NOT NULL AND published_at IS NULL
		ORDER BY epoch_generation, epoch_timeline, seq LIMIT :batch;
ROLLBACK;
