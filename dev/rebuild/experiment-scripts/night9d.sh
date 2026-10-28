#!/bin/bash
# Step 9, the probes' S column again, one batch (step9-plan.md 8.7): D9-probe-S, P9-probe-S and K9-probe-S could not
# come up in the probe batch of 2026-10-28 (probe-go2's 3.2.20 image ran the 3.2.19 probe), so the whole S layer runs
# again with the probes at 3.2.21, the four rows next to each other; L9-probe-S runs again too so that the layer is one
# batch. Same parameters as night9c.sh. About 75 minutes.
# Usage: night9d.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
IDLE=300 OPS=echo-1k-grpc,echo-1k-http,write,relay LOADS=200 "$X/probe9.sh" "$OUT/probes" \
  D9-probe-S P9-probe-S K9-probe-S L9-probe-S
echo "NIGHT probes done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
