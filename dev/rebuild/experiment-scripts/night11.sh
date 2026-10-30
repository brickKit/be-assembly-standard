#!/bin/bash
# Step 11 (step11-plan.md), suite C: the D and K rows' S, H and X cells under the background load, each with every
# fault (runner11.sh: R1 and R2, then R3, R5 on H and X, R4 last), one batch per row: d = D9-S, D9-H, D9-X (Docker);
# k = K9-S, K9-H, K9-X (single-node minikube). About 7.5 hours.
# Usage: night11.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit, night-wrap.sh)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
"$X/runner11.sh" "$OUT/d" D9-S D9-H D9-X
echo "NIGHT d done exit=$? $(date -Is)" >> "$OUT/night.log"
"$X/runner11.sh" "$OUT/k" K9-S K9-H K9-X
echo "NIGHT k done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
