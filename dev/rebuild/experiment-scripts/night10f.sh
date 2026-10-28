#!/bin/bash
# Step 10 (step10-plan.md 5.8): the outbox poll before and after P6.32, one batch: D9-S-sdk35 (be-sdk-go 3.0.0-alpha.35,
# every 250 ms poll numbers every partition) and D9-S (alpha.36, only the partitions with rows), one each, about
# 1.9 hours.
# Same flow and load as step 9 (runner9.sh: empty idle, seeded idle, the 7/s mix).
# Usage: night10f.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
"$X/runner9.sh" "$OUT/p632" D9-S-sdk35 D9-S
echo "NIGHT p632 done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
