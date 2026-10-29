#!/bin/bash
# Step 10 (experiment-plan.md, the LD and LP rows): their H and X columns, which step 9 left unmeasured, each row in a
# batch of its own with the pure form's S as the reference and the row's own S again, so that the columns compare
# within the row and the row against the pure form, all in one batch: ld = D9-S, LD9-S, LD9-H, LD9-X (the rest in
# Docker); lp = P9-S, LP9-S, LP9-H, LP9-X (the rest in rootless Podman). What runs on this machine: S and X, sales and
# inventory alone; H, the trading shell be/go-core. Same flow and load as step 9 (runner9.sh). About 6.8 hours.
# Usage: night10g.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
"$X/runner9.sh" "$OUT/ld" D9-S LD9-S LD9-H LD9-X
echo "NIGHT ld done exit=$? $(date -Is)" >> "$OUT/night.log"
"$X/runner9.sh" "$OUT/lp" P9-S LP9-S LP9-H LP9-X
echo "NIGHT lp done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
