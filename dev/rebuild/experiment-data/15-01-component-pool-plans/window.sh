#!/bin/bash
# How long a cached generic plan stays bad after a backlog arrives, with autovacuum on (PostgreSQL 16, naptime 60 s,
# analyze threshold 50 + 10 %): the queue claim, prepared, one client, rolled-back claims, plan_cache_mode = auto.
# The bus starts with 20 deliveries, analyzed (as autovacuum leaves a small table); pgbench runs 150 s with a progress
# line every 5 s; 15 s in, 20 000 deliveries arrive. The last analyze time of the delivery table is printed every
# 5 s. Performance power mode, restored on exit.
set -e
cd "$(dirname "$0")"
PW=$(grep '^POSTGRES_PASSWORD=' ../../../../.env | cut -d= -f2- | tr -d "\"'")
before=$(powerprofilesctl get); trap 'powerprofilesctl set "$before"' EXIT; powerprofilesctl set performance
echo "power mode: $(powerprofilesctl get) (was $before); $(date -Is)"
psql_() { docker exec -i -e PGPASSWORD="$PW" be-postgres psql -X -q -At -U postgres -d be_sdk_test "$@"; }
psql_ < window-bus-setup.sql > /dev/null 2>&1
docker cp -q bench-bus-claim.sql be-postgres:/tmp/bench-bus-claim.sql
docker exec -e PGPASSWORD="$PW" -e PGOPTIONS="-c search_path=t3_win -c plan_cache_mode=auto" be-postgres \
  pgbench -n -M prepared -c 1 -T 150 -P 5 -U postgres -D durable=d -D maxdeliver=3 -D ackwait=30 \
  -D token=0190f3a1-0000-7000-8000-0000000000a1 -f /tmp/bench-bus-claim.sql be_sdk_test 2>&1 | sed 's/^/pgbench: /' &
bench=$!
for i in $(seq 1 30); do
  sleep 5
  [ $i -eq 3 ] && { psql_ < window-bus-grow.sql > /dev/null; echo "t=15s: 20 000 deliveries arrived $(date +%T)"; }
  echo "t=$((i*5))s last_autoanalyze=$(psql_ -c "select coalesce(last_autoanalyze::text, '-') || ' n_mod=' || n_mod_since_analyze from pg_stat_user_tables where schemaname = 't3_win' and relname = 'be_bus_delivery'")"
done
wait $bench
psql_ -c "DROP SCHEMA t3_win CASCADE" > /dev/null 2>&1
