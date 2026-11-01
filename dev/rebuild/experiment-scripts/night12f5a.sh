#!/bin/bash
# Step 12, F5, round 1 (step12-plan.md 9.1): does the SDK version alone change a probe's base cost? The probes ran alone
# on old SDKs (Go alpha.23, Python a20) while a shell compiled them at its own, so step 9's "alone against shell"
# compared two SDKs too. Four base cells (idle 300 s, as night9c.sh): the Go probe on alpha.23 and alpha.37, the Python
# probe on a20 and a33, each pair next to each other; two passes, the second with each pair the other way round.
# About 60 minutes.
# Usage: night12f5a.sh <out>   (CONF: a snapshot of the conformance tools; run it under night-wrap.sh and systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
IDLE=300 OPS=echo-1k-grpc LOADS=200 "$X/probe9.sh" "$OUT/probes-p1" \
  D12-f5-base-go-a23 D12-f5-base-go-a37 D12-f5-base-py-a20 D12-f5-base-py-a33
echo "NIGHT pass 1 done exit=$? $(date -Is)" >> "$OUT/night.log"
IDLE=300 OPS=echo-1k-grpc LOADS=200 "$X/probe9.sh" "$OUT/probes-p2" \
  D12-f5-base-go-a37 D12-f5-base-go-a23 D12-f5-base-py-a33 D12-f5-base-py-a20
echo "NIGHT pass 2 done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
