#!/bin/bash
# Step 9, the probes in one batch (step9-plan.md 8.7): every row (D, P, K, L) at every layer, so each comparison has
# its reference in the same batch. Ordered by layer, the rows of a layer next to each other: the base costs (7 cells
# per row, idle 5 min), then the S column, then the H2 column (four operations at 200/s). The second night's probes
# stay as raw data and are not mixed into this batch's tables. probe9.sh starts minikube before the K cells and stops
# it before the others (three starts). About 5.5 hours.
# Usage: night9c.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
ROWS="D9-probe P9-probe K9-probe L9-probe"
base() { for k in go py goshell-1 goshell-2 goshell-4 pyshell-1 pyshell-2; do echo "$1-base-$k"; done; }
IDLE=300 OPS=echo-1k-grpc,echo-1k-http,write,relay LOADS=200 "$X/probe9.sh" "$OUT/probes" \
  $(for r in $ROWS; do base $r; done) $(for r in $ROWS; do echo "$r-S"; done) $(for r in $ROWS; do echo "$r-H2"; done)
echo "NIGHT probes done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
