#!/bin/bash
# Commits a second of a one-row insert: alone, with pg_notify in the same statement (as the PostgreSQL queue's publish
# does), and with pg_notify as a second statement after the insert committed (a transaction without a transaction ID);
# at 1, 8, 16 and 32 clients; pgbench, 20 s a run, the three alternating five times. One session LISTENs
# throughout, as a subscriber would (without a listener NOTIFY still queues). Needs a PostgreSQL container ($PG, default
# be-postgres) whose postgres user may create a database. Writes results.tsv next to this script.
set -euo pipefail
cd "$(dirname "$0")"; PG=${PG:-be-postgres}; DB=notifybench
psql() { docker exec -i "$PG" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
psql -d $DB < setup.sql
docker exec "$PG" psql -U postgres -At -c 'SELECT version()' > version.txt
for f in insert.sql notify.sql notify-after.sql; do docker cp "$f" "$PG:/tmp/nb-$f"; done
# a listener that stays connected for the whole run and drains notifications
( printf "LISTEN be_bus_wake;\nSELECT pg_sleep(600);\n" | psql -d $DB > /dev/null 2>&1 ) & L=$!
trap 'kill $L 2>/dev/null || true' EXIT
sleep 1
printf 'clients\tkind\trun\ttps\tlatency_ms\n' > results.tsv
for c in 1 8 16 32; do for r in 1 2 3 4 5; do for k in insert notify notify-after; do
  out=$(docker exec "$PG" pgbench -U postgres -n -c $c -j $(( c < 8 ? c : 8 )) -T 20 -f "/tmp/nb-$k.sql" $DB 2>&1)
  tps=$(echo "$out" | sed -n 's/^tps = \([0-9.]*\).*/\1/p'); lat=$(echo "$out" | sed -n 's/^latency average = \([0-9.]*\) ms/\1/p')
  printf '%s\t%s\t%s\t%s\t%s\n' $c $k $r "$tps" "$lat" >> results.tsv
  psql -d $DB -c "TRUNCATE msg"
done; done; done
kill $L 2>/dev/null || true
psql -c "DROP DATABASE $DB WITH (FORCE)"
