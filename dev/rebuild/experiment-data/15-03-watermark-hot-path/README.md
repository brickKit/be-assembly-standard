# The watermark consumer's hot paths (2026-11-03)

Foundations item 1, T7e. be-sdk-go at `dba96b3` (released as 3.0.0-alpha.51), PostgreSQL 16.15 (be-postgres), one
machine (12 CPUs); source and consumer schemas in the same database, the pull over a real system surface (mTLS on
loopback). `run.sh bench.out` runs the benchmarks of `projection/watermark_integration_test.go` three times, 200
operations each, in performance power mode (balanced before and restored after).

| operation | three runs (ms) |
| --- | --- |
| apply one event to a plain projection (`Projection.Apply` in its own transaction) | 0.704 / 0.707 / 0.676 |
| apply one event through the watermark consumer (`Watermarked.Handle`: the same plus the source's state, the failure check, the contiguous position, the digest tripwire) | 0.958 / 1.074 / 1.034 |
| one echo-only pull (record the pull, the source's check, echo and numbering, the page, the declaration, the echo applied) | 8.26 / 8.54 / 8.32 |
| one pull returning 100 rows and the echo | 59.5 / 57.3 / 63.0 |

What it means for the requirement: a watermark consumer pays about 0.3 ms more an event than a plain projection,
and a pull costs 8 ms plus about 0.5 ms a row. Security sources (organization, employees, identity) change rarely,
and a consumer pulls each source once every half of its freshness, so neither is a hot spot at the expected scale;
the spread between runs is up to 12 % (the watermarked apply: 0.958-1.074 ms; the pull of 100 rows: 10 %), well below the differences.

Not optimized, candidates if a source's event rate grows: each applied row runs about six statements (the state is
read per transaction for every partition, the failure check, the projection's own lock and read and write, the
contiguous position, the tripwire's read); batching a page's rows into fewer statements, reading only the row's
partition, and folding the failure check into the position update would remove most of them.
