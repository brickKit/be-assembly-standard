#!/bin/bash
# Publish throughput of the PostgreSQL queue (BenchmarkConcurrentPublish, 8 publishers): cached prepared statements
# against plan_cache_mode=force_custom_plan on the bus connections. Paired, alternated, performance power mode.
set -u
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-go && source ../../dev/rebuild/experiment-scripts/itenv.sh
OUT=$1; PREV=$(powerprofilesctl get); trap 'powerprofilesctl set "$PREV"' EXIT
powerprofilesctl set performance; echo "# power: $PREV -> $(powerprofilesctl get); $(date -Is)" >> "$OUT"
B=$(dirname "$OUT")/pgqueue.test; go test -c -tags integration -o "$B" ./events/pgqueue/ || exit 1
for round in 1 2 3 4; do for mode in prepared custom; do
  unset DEBUG_B7C1_MODE; [ $mode = custom ] && export DEBUG_B7C1_MODE=custom
  echo "round=$round mode=$mode $("$B" -test.run '^$' -test.bench BenchmarkConcurrentPublish -test.benchtime 5000x 2>&1 | grep -oE '[0-9.]+ msgs/s')" >> "$OUT"
done; done
