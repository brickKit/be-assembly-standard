# The SDK's statements on a component's pool: cached plans and the queue indexes (2026-11-02)

Foundations item 1, T3. PostgreSQL 16.15 (be-postgres, autovacuum on, naptime 60 s, analyze threshold 50 + 10 %),
one machine. The scripts read the SDK migrations from `tools/be-protocol/migrations` (and `migrations-bus`); every
number below was measured with protocol alpha.44's files (0001-0009, migrations-bus 0001-0003), before 0010 and
0004 existed. To rerun them as measured, check out be-protocol `v3.0.0-alpha.44` first; with alpha.45 the
"current" outbox index is already the candidate one. Raw outputs are the `.out` files next to their scripts.

## What runs on the pool

`gen.py` -> `plans-<mode>[-analyzed].{sql,out}`: the forwarder's numbering and read of unpublished rows, the work
claim, the audit numbering and transfer read, as prepared statements on a fresh schema, autovacuum off; eight
executions on a small backlog (the plan settles after five), EXPLAIN ANALYZE, the backlog grows to 20 000, three
executions, EXPLAIN ANALYZE. Numbering (outbox and audit) and the audit transfer read follow their partial
indexes in order at both sizes, in both plan cache modes. Two statements do not:

- **work claim**, `auto` (cached generic plan settled on 20 rows): the final `UPDATE ... FROM c` joins the claimed
  item back by a sequential scan of the whole table, 2.8-3.1 ms with 20 000 (`plans-auto.out`,
  `plans2-auto-*.out`). `force_custom_plan` on a never-analyzed table: the due path bitmap-scans and sorts the whole
  backlog, 7.4-10.7 ms (`plans-force_custom_plan.out`, `plans2-force_custom_plan-current.out`), because the
  `job = ANY($1)` filter gets the default selectivity without statistics; analyzed once at the small size
  (`plans2-*-current-analyze-small.out`) the custom plan is 0.33 ms, the generic one still 4.1 ms (the expired path
  becomes a sequential scan too). After an analyze at the large size both are 0.19-0.31 ms
  (`plans-*-analyzed.out`): the analyze invalidates the cached plan.
- **forwarder read of unpublished rows** (`gen2.py` -> `plans2-*.out`): the index was `(stream, partition, seq)`,
  the statement orders by `(epoch_generation, epoch_timeline, seq)`. With 20 000 published rows (kept for the
  redelivery retention) ahead of 600 unpublished: the generic plan walks the position index past all of them
  ("Rows Removed by Filter: 20000"), 3.0-3.1 ms; the custom plan on a never-analyzed table sorts every
  unpublished row instead (fine with 600, a whole backlog when the bus is down), and analyzed once at the small
  size it walks the published rows too, 2.97 ms (`plans2-force_custom_plan-current-analyze-small.out`). The candidate index `(stream, partition, epoch_generation, epoch_timeline,
  seq) WHERE seq IS NOT NULL AND published_at IS NULL` reads in order in both modes, 0.2 ms
  (`plans2-*-candidate.out`). A candidate due index `(run_at, job)` for the work claim did not help
  (`plans2-force_custom_plan-candidate.out`, 7.9 ms).

## What planning every statement costs

`bench.sh` -> `bench.out` (`bench-summary.txt` without the schema notices): pgbench, prepared statements, one client,
3000 rolled-back transactions per run, a schema built afresh for every run (a rolled-back claim leaves a dead row
version: reusing one schema slowed run after run, `bench-drifting.out`), analyzed, 20 000 waiting; `auto` and
`force_custom_plan` alternate, three pairs; performance power mode (restored to balanced on exit).

| statement | auto | force_custom_plan |
| --- | --- | --- |
| work claim | 0.218 / 0.218 / 0.500 ms | 0.539 / 0.562 / 0.676 ms |
| unpublished read, alpha.44 index | 3.340 / 3.660 / 3.605 ms | 0.972 / 1.552 / 1.022 ms |
| unpublished read, candidate index | 0.589 / 0.806 / 0.579 ms | 0.964 / 1.677 / 1.025 ms |

`bench-bus.sh` -> `bench-bus.out`: the PostgreSQL queue's claim (be-sdk-go alpha.48's statement), same method:
`auto` 0.134 / 0.150 / 0.141 ms, `force_custom_plan` 0.430 / 0.452 / 0.420 ms. alpha.44 set `force_custom_plan` on
the bus pool, so every claim paid about 0.3 ms of planning; that decision rested on publish throughput only
(`../14-07-pgqueue-plan/measure-publish.out`).

## How long a stale cached plan lasts

`window.sh` -> `window-bus.out`: the queue claim with `auto`, autovacuum on as configured; 20 deliveries analyzed,
pgbench 150 s with a progress line every 5 s; 20 000 deliveries arrive at t = 15 s (22:52:44). Claims took
4.9-6.8 ms from then until autovacuum analyzed the table at 22:53:07 (23 s later; at most a naptime), then
0.124-0.156 ms. The latency before the arrival rises from 0.26 to 0.64 ms with the dead row versions of the
rolled-back claims.

## The fix and its checks

The maintainer chose cached plans with the SDK analyzing lagging tables itself (P5.33, protocol alpha.45):
`function-prototype.{sql,out}` is the function on a fresh schema (2.87 ms -> 0.25 ms after one call, 0.18 ms once
the plan settled again; nothing under 1000 changed rows, nothing again within 30 s, nothing for a temporary table
of the same name). Mutation checks of the new tests (each test red with the change undone, the file restored after):

- `t3-work-mutation.txt`: work claim without the upkeep, 5 of 5 red (2.96-3.18 ms against 0.83-1.15 ms).
- `t3-pgqueue-mutation.txt`: queue claim without the upkeep, 5 of 5 red (3.99-5.06 ms against 0.60-0.84 ms).
- `t3-outbox-mutation.txt`: forwarder read with the alpha.44 index, 5 of 5 red (3.87-4.66 ms against 0.91-1.34 ms).
- `t3-wiring-mutation.txt`, `t3-bus-wiring-mutation.txt`: a component and a transport without the loop never analyze.
- `t3-py-mutations.txt`: the same four for be-sdk-python, 3 of 3 red each.

The Go and Python integration tests ran in balanced power mode (not switched: correctness, with margins of
several times the spread).
