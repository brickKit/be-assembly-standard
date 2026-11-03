#!/usr/bin/env bash
# be_analyze_stale() against the by-oid candidate, in the idle measurement's database (run idle/ once first), pgbench
# inside the be-postgres container, prepared statements, alternating, performance power mode (restored on exit).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mode=$(powerprofilesctl get); trap 'powerprofilesctl set "$mode"' EXIT; powerprofilesctl set performance
docker exec -i be-postgres psql -q -U postgres -d be_idle_bench < "$here/stale-candidate.sql"
for f in be_analyze_stale be_analyze_stale_byoid; do
  printf 'BEGIN;\nSELECT idle.%s();\nCOMMIT;\n' "$f" | docker exec -i be-postgres sh -c "cat > /tmp/$f.sql"
done
echo "# $(date -Is) power mode: $(powerprofilesctl get); tables in the database: $(docker exec be-postgres psql -U postgres -d be_idle_bench -Atc 'select count(*) from pg_class')"
for i in 1 2 3; do
  for f in be_analyze_stale be_analyze_stale_byoid; do
    echo -n "$f run $i: "
    docker exec be-postgres pgbench -U postgres -n -M prepared -t 5000 -f /tmp/$f.sql -r be_idle_bench 2>&1 | grep -E 'SELECT idle' | awk '{print $1 " ms"}'
  done
done
