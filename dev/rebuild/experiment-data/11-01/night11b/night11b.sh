#!/bin/bash
# night11 re-run: K9-H's R5 (split) and R4 (upgrade) with be-acceptance v1.0.11 (nodeports skips a shell that left)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
FAULTS=split,upgrade "$X/runner11.sh" "$OUT/k" K9-H
echo "NIGHT k done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
