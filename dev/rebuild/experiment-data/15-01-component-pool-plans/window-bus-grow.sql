SET search_path = t3_win;
WITH m AS (INSERT INTO be_bus_message (subject, headers, data)
  SELECT 'be.x.0.t.v1', '{}'::jsonb, '\x7b7d'::bytea FROM generate_series(1, 20000) RETURNING seq)
INSERT INTO be_bus_delivery (durable, seq) SELECT 'd', seq FROM m;
