#!/usr/bin/env bash
# The idle claim (idle-claim.sql: nothing due, rolled back) with be_current_db_epoch() VOLATILE as migrated and
# STABLE, alternating, pgbench inside be-postgres, prepared, 3000 transactions a run, performance power mode
# (restored on exit). Needs the idle measurement's database (run idle/ once first); restores VOLATILE at the end.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mode=$(powerprofilesctl get); trap 'docker exec be-postgres psql -qU postgres -d be_idle_bench -c "ALTER FUNCTION idle.be_current_db_epoch() VOLATILE"; powerprofilesctl set "$mode"' EXIT
powerprofilesctl set performance
docker cp "$here/idle-claim.sql" be-postgres:/tmp/idle-claim.sql
echo "# $(date -Is) power mode: $(powerprofilesctl get)"
docker exec be-postgres psql -U postgres -d be_idle_bench -c "SET search_path = idle" \
  -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM be_current_db_epoch()" -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM be_current_db_epoch()" \
  -c "EXPLAIN (ANALYZE, BUFFERS) SELECT g.generation, ('x' || substr(pg_walfile_name(pg_current_wal_lsn()), 1, 8))::bit(32)::bigint FROM be_recovery_generation g"
for i in 1 2 3; do
  for v in VOLATILE STABLE; do
    docker exec be-postgres psql -qU postgres -d be_idle_bench -c "ALTER FUNCTION idle.be_current_db_epoch() $v"
    echo -n "$v run $i: "
    docker exec be-postgres pgbench -U postgres -n -M prepared -t 3000 -f /tmp/idle-claim.sql -r be_idle_bench 2>&1 | grep -E 'WITH expired' | awk '{print $1 " ms"}'
  done
done
