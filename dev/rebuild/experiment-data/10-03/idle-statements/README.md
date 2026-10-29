# Idle statements before and after P6.32

D9-S with seed data, 90 s settle, `pg_stat_statements` reset, 60 s idle, read by role (`experiment-scripts/idle-statements.sh`).

- `before/` 2026-10-28 18:10, components on be-sdk-go 3.0.0-alpha.35 / be-sdk-python 3.0.0a31 (erp/sales 3.0.12, ...).
- `after/` 2026-10-28 18:36, on alpha.36 / a32 (erp/sales 3.0.13, ...). `after/` has no `top.txt` or `work.txt`.
- `totals.txt`: the sum of `by-role.txt`'s calls column, and per second.
