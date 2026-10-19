WITH m AS (INSERT INTO msg (id, stream, payload) VALUES (gen_random_uuid(), 'orders', repeat('x', 200)) ON CONFLICT DO NOTHING RETURNING 1)
SELECT count(*) FROM m;
