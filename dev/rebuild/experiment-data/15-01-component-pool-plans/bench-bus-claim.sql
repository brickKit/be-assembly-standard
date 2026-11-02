BEGIN;
WITH ready AS (SELECT seq FROM be_bus_delivery WHERE durable = :durable AND NOT in_flight
				AND not_before <= clock_timestamp() ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED),
			expired AS (SELECT seq FROM be_bus_delivery WHERE durable = :durable AND in_flight AND lease_until < clock_timestamp()
				AND attempts < :maxdeliver ORDER BY seq LIMIT 1 FOR UPDATE SKIP LOCKED),
			due AS (SELECT min(seq) AS seq FROM (SELECT seq FROM ready UNION ALL SELECT seq FROM expired) c),
		claimed AS (UPDATE be_bus_delivery d SET in_flight = true, attempts = d.attempts + 1, lease_token = :token,
			lease_until = clock_timestamp() + make_interval(secs => :ackwait)
			WHERE d.durable = :durable AND d.seq = (SELECT seq FROM due) RETURNING d.seq, d.attempts)
		SELECT c.seq, c.attempts, m.subject, m.headers, m.data FROM claimed c
			LEFT JOIN be_bus_message m ON m.seq = c.seq;
ROLLBACK;
