#!/bin/bash
# Step 10, B5 (step10-plan.md): how resources grow with the load and with the data, one batch. Every cell runs the
# step 9 flow with the 7/s mix (20 users) and then a 14/s mix (40 users) on the same data (RATE2): D9-S and D9-X on
# the step 8 baseline, D9-S-x2 and D9-X-x2 on twice the data (baseline_scale 2; their digests are compared with each
# other, REF=first). Load against load on the same cell, data against data at the same load. About 4.5 hours.
# Usage: night10b.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
RATE2=14 USERS2=40 "$X/runner9.sh" "$OUT/b5-x1" D9-S D9-X
echo "NIGHT b5-x1 done exit=$? $(date -Is)" >> "$OUT/night.log"
REF=first RATE2=14 USERS2=40 "$X/runner9.sh" "$OUT/b5-x2" D9-S-x2 D9-X-x2
echo "NIGHT b5-x2 done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
