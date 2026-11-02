#!/bin/bash
# The PostgreSQL queue's claim (be-sdk-go alpha.48's Transport.claim) in the steady state (analyzed, 20 000 waiting):
# a cached generic plan against planning each claim (force_custom_plan, what the bus pool sets since alpha.44).
# pgbench, prepared statements, one client, rolled-back claims, a schema built afresh for every run; three pairs,
# alternating. Switches to the performance power mode and restores the previous one on exit.
set -e
cd "$(dirname "$0")"
PW=$(grep '^POSTGRES_PASSWORD=' ../../../../.env | cut -d= -f2- | tr -d "\"'")
before=$(powerprofilesctl get); trap 'powerprofilesctl set "$before"' EXIT; powerprofilesctl set performance
echo "power mode: $(powerprofilesctl get) (was $before)"
docker cp -q bench-bus-claim.sql be-postgres:/tmp/bench-bus-claim.sql
for pair in 1 2 3; do
  for mode in auto force_custom_plan; do
    docker exec -i -e PGPASSWORD="$PW" be-postgres psql -X -q -U postgres -d be_sdk_test < bench-bus-setup.sql > /dev/null 2>&1
    docker exec -e PGPASSWORD="$PW" -e PGOPTIONS="-c search_path=t3_bus -c plan_cache_mode=$mode" be-postgres \
      pgbench -n -M prepared -c 1 -t 3000 -U postgres -D durable=d -D maxdeliver=3 -D ackwait=30 \
      -D token=0190f3a1-0000-7000-8000-0000000000a1 -f /tmp/bench-bus-claim.sql be_sdk_test 2>&1 |
      grep -E 'latency average' | sed "s/^/bus claim pair $pair $mode: /"
  done
done
docker exec -e PGPASSWORD="$PW" be-postgres psql -X -q -U postgres -d be_sdk_test -c "DROP SCHEMA t3_bus CASCADE" > /dev/null 2>&1
