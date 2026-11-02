# be-sdk-go events/pgqueue: two flaky tests (2026-11-02)

- `loop-purge.sh`: one message of another stream, 9 days old, in the shared test bus makes
  TestPurgeDropsMessagesPastTheRetention fail at once (expected 1, actual 2): Purge counts the whole bus.
- `claim-prepared.txt`: the claim as a prepared statement, delivery statistics analyzed while empty, 20 000 waiting:
  the first five executions are planned for their parameters; from the sixth PostgreSQL uses a generic plan that
  bitmap-scans the whole backlog (19 991 rows; 80 000 index entries with the dead ones) and sorts it, about 7 ms a
  claim. `claim-plans.txt`: the same statement with literals plans well with stale and fresh statistics (0.2 ms).
- `measure-claim.sh` / `.out` (prepared against re-planned with CacheDescribe) and `measure-claim2.out` (plus
  force_custom_plan): medians of TestABacklogDoesNotSlowEachClaim, 5 runs per cell, 3 alternated rounds,
  performance power mode. With stale statistics: prepared 761 µs (20) / 4281 µs (20 000), 8 of 15 failing;
  CacheDescribe 1027 / 1165 µs; force_custom_plan 917 / 920 µs. The "fresh" cells are disturbed by the set-up itself
  (small backlog 2 to 17 ms in every mode) and are not used.
- `measure-publish.sh` / `.out`: BenchmarkConcurrentPublish (8 publishers, 5000 messages), 4 alternated rounds,
  performance mode: prepared 12 528 to 13 800 msgs/s, force_custom_plan 12 906 to 13 109 msgs/s.
- On the test's own fresh bus, before the fix: 17 of 20 runs red; after (force_custom_plan): 0 of 20.
