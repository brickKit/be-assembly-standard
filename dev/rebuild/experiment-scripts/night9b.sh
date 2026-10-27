#!/bin/bash
# Step 9, the second night (step9-plan.md 8.6): the LD and LP cells with a same-version P9-S as their reference
# (runner9.sh, the business chain), then the probes of the P, K and L rows, reduced: base costs idle 5 min; the
# communication breakdown on the S and H2 columns, four operations at 200/s (probe9.sh). About 7.5 hours.
# Usage: night9b.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
"$X/runner9.sh" "$OUT/chain" LD9-S LP9-S P9-S; echo "NIGHT chain done exit=$? $(date -Is)" >> "$OUT/night.log"
base() { for k in go py goshell-1 goshell-2 goshell-4 pyshell-1 pyshell-2; do echo "$1-base-$k"; done; }
IDLE=300 OPS=echo-1k-grpc,echo-1k-http,write,relay LOADS=200 "$X/probe9.sh" "$OUT/probes" \
  $(for r in P9-probe K9-probe L9-probe; do base $r; echo "$r-S" "$r-H2"; done)
echo "NIGHT probes done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
