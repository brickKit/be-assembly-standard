#!/bin/bash
# Claim latency of the PostgreSQL queue (be-sdk-go events/pgqueue, TestABacklogDoesNotSlowEachClaim's medians): cached
# prepared statements (pgx's default) against re-planning each execution (QueryExecModeCacheDescribe), with the
# delivery table's statistics stale (analyzed while empty) and fresh (analyzed after the insert). Paired, alternated,
# in performance power mode (restored at the end, also when stopped).
set -u
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-go && source ../../dev/rebuild/experiment-scripts/itenv.sh
OUT=${1:-/dev/stdout}; PREV=$(powerprofilesctl get); trap 'powerprofilesctl set "$PREV"' EXIT
powerprofilesctl set performance; echo "# power: $PREV -> $(powerprofilesctl get); $(date -Is)" >> "$OUT"
PW=$(grep '^POSTGRES_PASSWORD=' /home/zhijie/Desktop/github/be-assembly-standard/.env | cut -d= -f2- | tr -d "\"'")
reset() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_sdk_test -qAtc "DELETE FROM be_bus_test.be_bus_delivery WHERE durable LIKE 'backlog_%'; ANALYZE be_bus_test.be_bus_delivery"; }
go test -c -tags integration -o /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/pgqueue.test ./events/pgqueue/ || exit 1
for round in 1 2 3; do for stats in stale fresh; do for mode in prepared describe custom; do
  reset; unset DEBUG_B7C1_ANALYZE DEBUG_B7C1_MODE; [ $stats = fresh ] && export DEBUG_B7C1_ANALYZE=1; [ $mode != prepared ] && export DEBUG_B7C1_MODE=$mode
  r=$(/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/pgqueue.test -test.count=5 -test.v -test.run 'TestABacklogDoesNotSlowEachClaim$' 2>&1)
  echo "round=$round stats=$stats mode=$mode fails=$(echo "$r" | grep -c -- '--- FAIL') $(echo "$r" | grep -oE 'small=[^ ]+ large=[^ ]+' | tr '\n' ' ')" >> "$OUT"
done; done; done
