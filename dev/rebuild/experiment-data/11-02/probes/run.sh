#!/bin/bash
# K probes check (11-01, section 8): a sales crash under the background load on K9-S, three times with the probes
# BrickKit writes (default) and three times with faster ones (fast), alternating; each probe change rolls out a new
# Pod first, so every crash is a Pod's first (no restart back-off)
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"; echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
C="process_crashes and sales"; P="sh:probes11.sh K9-S erp/sales"
FAULTS="$C,$P fast,$C,$P default,$C,$P fast,$C,$P default,$C,$P fast,$C" "$X/runner11.sh" "$OUT/k" K9-S
echo "NIGHT k done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
