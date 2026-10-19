#!/bin/bash
# Claim latency of the OR claim against the split claim, for backlogs of 40, 2000 and 20000 due items: pgbench, one
# client, 5 s per run, the two alternating three times. Needs a running PostgreSQL container ($PG, default be-postgres)
# whose postgres user may create a database. Writes results.tsv and plans.txt next to this script.
set -euo pipefail
cd "$(dirname "$0")"; PG=${PG:-be-postgres}; DB=claimbench
psql() { docker exec -i "$PG" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
docker exec "$PG" psql -U postgres -At -c 'SELECT version()' > version.txt
for f in claim-or.sql claim-split.sql; do docker cp "$f" "$PG:/tmp/$f"; done
printf 'backlog\tclaim\trun\ttps\tlatency_ms\n' > results.tsv; : > plans.txt
for n in 40 2000 20000; do
  psql -d $DB -v n=$n < setup.sql
  for c in or split; do
    echo "== backlog $n, claim $c" >> plans.txt
    sed -e '/^BEGIN;$/d' -e '/^ROLLBACK;$/d' -e 's/^WITH/EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) WITH/' "claim-$c.sql" \
      | sed '1i BEGIN;' | sed '$a ROLLBACK;' | psql -d $DB >> plans.txt
  done
  for r in 1 2 3; do for c in or split; do
    out=$(docker exec "$PG" pgbench -U postgres -n -c 1 -T 5 -f "/tmp/claim-$c.sql" $DB 2>&1)
    tps=$(echo "$out" | sed -n 's/^tps = \([0-9.]*\).*/\1/p'); lat=$(echo "$out" | sed -n 's/^latency average = \([0-9.]*\) ms/\1/p')
    printf '%s\t%s\t%s\t%s\t%s\n' $n $c $r "$tps" "$lat" >> results.tsv
  done; done
done
psql -c "DROP DATABASE $DB"
