# What an idle member's background work costs the database, before and after P7.23 (2026-11-03)

Foundations item 1, T5 ②. PostgreSQL 16.15 (be-postgres, pg_stat_statements preloaded), one machine, 12 CPUs.
"Before" is be-sdk-go `v3.0.0-alpha.49` (a git worktree of the tag), "after" the working tree that became
alpha.50 (protocol alpha.47 for P7.23; the measured binary still ran the alpha.45 migrations, so the statistics
check is the old function in both).

## The member

`idle/main.go`: one member with a queue job, a cron job (`*/5 * * * *`), a singleton (hourly), the SDK's runner at
its defaults (4 workers, 500 ms poll), and the statistics upkeep of P5.33 (`-statistics`); nothing is due. It
provisions its own database `be_idle_bench` and schema `idle` the way the assembly does, warms up 5 s, then counts
for 60 s: statements and their execution time from pg_stat_statements (this database only, the program's own reads
left out), transactions from pg_stat_database, the CPU of the process (getrusage) and of the member's backends
(`/proc/<pid>/stat` inside the container, 10 ms ticks). Build: `go build` in `idle/` (its `go.mod` replaces the SDK
with the assembly project's `tools/be-sdk-go`; the "before" binary was built with a modfile pointing at the tag's
worktree). `BE_SDK_TEST_PG_ADMIN` is a superuser DSN.

`run.sh <before> <after> <out> 60 3` -> `idle.out`: three pairs, alternating, performance power mode (balanced
before and restored after).

| per second | before (three runs) | after (three runs) |
| --- | --- | --- |
| statements | 41.60 / 41.60 / 41.60 | 10.80 / 10.47 / 10.80 |
| claims | 8.33 | 2.13 / 2.10 / 2.13 |
| cron watermark transactions | 1.03 | 0.02 (one slot in the minute: the 5-minute boundary) |
| execution time on the server | 1.962 / 1.907 / 1.963 ms | 0.839 / 0.845 / 0.765 ms |
| member process CPU | 7.179 / 7.148 / 7.100 ms | 1.697 / 1.590 / 1.704 ms |
| member backends' CPU | 5.500 / 5.167 / 5.167 ms | 2.000 / 1.833 / 1.833 ms |

The spread between runs of the same binary is under 7 %, the differences are 2-4 times. `transactions/s` in the
output is the whole database (pg_stat_database), not only the member: 9.9 before against 9.88 `begin`s, 4.0 after
against 2.6-2.7, so about 1.3 a second come from elsewhere (not chased). After the change the statistics check
`be_analyze_stale()` (0.52 a second, 0.66-0.94 ms a call) is half the remaining execution time.

## The statistics check

`stale-candidate.sql`, `bench-stale.sh` -> `bench-stale.out`: the alpha.45 function against one that reads the same
numbers by oid from the statistics functions (`pg_stat_get_mod_since_analyze`, `pg_stat_get_last_analyze_time`,
`pg_stat_get_last_autoanalyze_time`, `pg_class.reltuples`) instead of three reads of `pg_stat_all_tables`; pgbench
inside the container, prepared, 5000 transactions a run, three pairs alternating, performance mode, 498 relations in
the database: 0.208 / 0.177 / 0.189 ms against 0.062 / 0.060 / 0.055 ms. The decision is the same (protocol
alpha.47's `migrations/0011`, `migrations-bus/0005`).

In the member (a call every 2 s on pooled connections): `run.sh <after> <after2> idle-stats.out 60 3 view-check
oid-check`, both binaries with P7.23, `after2` built once the SDK pinned protocol alpha.47 (its migrations carry
0011): a call 0.747 / 0.599 / 0.645 ms with the view, 0.260 / 0.276 / 0.178 ms by oid; the member's execution time
0.804 / 0.756 / 0.751 ms against 0.561 / 0.517 / 0.470 ms a second. The CPU readings differ by less than their
10 ms ticks: no difference seen there.

## Not taken

`bench-epoch.sh` -> `bench-epoch.out`: marking `be_current_db_epoch()` STABLE so it could be inlined into the
claim. The function alone costs more than its body inlined (the EXPLAIN lines at the top of the output), but the
idle claim (`idle-claim.sql`) does not change with it: see the alternating runs.
