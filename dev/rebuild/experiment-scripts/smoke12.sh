#!/bin/bash
# Step 12 (step12-plan.md 9.1, item 2): suite D's smoke on the other rows: V4 on the P, L, LD, LP and K rows, V1 on P
# and K (runner12r.sh). The K row last: its minikube node publishes every component's host port (18600 and on), which
# the other rows' containers and forwarders bind too (smoke-try1 failed so), so the node starts only after them and
# stops at the end. smoke.log gets the outermost mark SMOKE12 ALL-DONE.
# Usage: smoke12.sh <out>
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/smoke.pid"; LOG=$OUT/smoke.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
say "SMOKE12 START"
"$X/runner12r.sh" "$OUT" P12-V4 P12-V1b L12-V4 LD12-V4 LP12-V4
if "$X/cluster-on.sh" "$OUT/cluster-on.log" > "$OUT/cluster-on.out" 2>&1; then say "SMOKE12 cluster on"; else say "SMOKE12 FAILED cluster-on"; fi
"$X/runner12r.sh" "$OUT" K12-V4 K12-V1b
say "SMOKE12 cells: $(grep -c ' DONE ' "$OUT/status.log") done; $(grep -cE 'FAILED|exit=[1-9]' "$OUT/status.log") with a failure"
minikube -p bek stop > "$OUT/cluster-off.log" 2>&1; say "SMOKE12 cluster off exit=$?"
say "SMOKE12 ALL-DONE"
