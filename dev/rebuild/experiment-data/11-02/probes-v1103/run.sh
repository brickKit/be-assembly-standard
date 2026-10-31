#!/bin/bash
# FRR-017 re-test on BrickKit v1.10.3: a sales crash under the background load on K9-S, three times with the probes
# 1.10.3 writes (readiness every 5 s; the first crash is on the Pod as brought up, unpatched) and three times with
# readiness every 1 s (fast), alternating; each probe change rolls out a new Pod first (no restart back-off). At the
# end the sales Pods' probe events, to see whether the readiness check kubelet runs right after the startup probe
# passes failed (/readyz answers ok only after the member started, /healthz as soon as it listens)
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"; echo "NIGHT START $(date -Is) brickkit=$(brickkit --version | head -1)" >> "$OUT/night.log"
C="process_crashes and sales"; P="sh:probes11.sh K9-S erp/sales"
FAULTS="$C,$P fast,$C,$P v1.10.3,$C,$P fast,$C,$P v1.10.3,$C,$P fast,$C,$P events" "$X/runner11.sh" "$OUT/k" K9-S
echo "NIGHT k done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
