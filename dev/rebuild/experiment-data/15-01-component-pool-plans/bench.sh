#!/bin/bash
# The cost of planning each SDK statement afresh (plan_cache_mode = force_custom_plan) against a cached generic plan,
# in the steady state (analyzed tables, 20 000 waiting): pgbench, prepared statements, one client, rolled-back
# transactions; auto and force_custom_plan alternate, three pairs each, every run on a schema built afresh (a
# rolled-back claim leaves a dead row version, so a reused schema slows run after run: bench-drifting.out). The read
# of unpublished rows runs with the current and the candidate index. EXPLAIN of each statement's generic plan. Switches to the performance power mode and restores the previous one on exit.
set -e
cd "$(dirname "$0")"
PW=$(grep '^POSTGRES_PASSWORD=' ../../../../.env | cut -d= -f2- | tr -d "\"'")
before=$(powerprofilesctl get); trap 'powerprofilesctl set "$before"' EXIT; powerprofilesctl set performance
echo "power mode: $(powerprofilesctl get) (was $before)"
for f in bench-claim.sql bench-unpublished.sql; do docker cp -q $f be-postgres:/tmp/$f; done
psql_() { docker exec -i -e PGPASSWORD="$PW" be-postgres psql -X -q -U postgres -d be_sdk_test "$@"; }
CANDIDATE="SET search_path = t3_bench; DROP INDEX be_outbox_unpublished; CREATE INDEX be_outbox_unpublished ON be_outbox
  (stream, partition, epoch_generation, epoch_timeline, seq) WHERE seq IS NOT NULL AND published_at IS NULL; ANALYZE be_outbox;"
run() {  # mode file label [candidate]
  psql_ < bench-setup.sql > /dev/null
  [ -n "$4" ] && psql_ -c "$CANDIDATE" > /dev/null
  docker exec -e PGPASSWORD="$PW" -e PGOPTIONS="-c search_path=t3_bench -c plan_cache_mode=$1" be-postgres \
    pgbench -n -M prepared -c 1 -t 3000 -U postgres -D jobs='{bulk,other}' -D holder=h -D lease=30 -D stream=s -D part=0 \
    -D batch=500 -f /tmp/$2 be_sdk_test 2>&1 | grep -E 'latency average' | sed "s/^/$3 $1: /"
}
for pair in 1 2 3; do
  for mode in auto force_custom_plan; do run $mode bench-claim.sql "claim pair $pair"; done
  for mode in auto force_custom_plan; do run $mode bench-unpublished.sql "unpublished(current index) pair $pair"; done
  for mode in auto force_custom_plan; do run $mode bench-unpublished.sql "unpublished(candidate index) pair $pair" c; done
done
psql_ < bench-setup.sql > /dev/null
echo "== generic plan of the claim in the steady state"
psql_ -c "SET search_path = t3_bench; SET plan_cache_mode = force_generic_plan;
  PREPARE c(text[], text, float8) AS $(sed -n '2,16p' bench-claim.sql | sed 's/:jobs/$1/g; s/:holder/$2/; s/:lease/$3/' | tr -d ';');
  BEGIN; EXPLAIN (ANALYZE, COSTS OFF) EXECUTE c('{bulk,other}', 'h', 30); ROLLBACK;"
psql_ -c "DROP SCHEMA t3_bench CASCADE" > /dev/null 2>&1
