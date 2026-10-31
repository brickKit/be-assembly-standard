#!/bin/bash
# D79 check: an inventory crash under the background load on D9-S and K9-S; the confirmations' processing window
# after it should be about 5 s (was 30-31 s in night11)
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"; echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
FAULTS="process_crashes and inventory" "$X/runner11.sh" "$OUT/d" D9-S; echo "NIGHT d done exit=$? $(date -Is)" >> "$OUT/night.log"
FAULTS="process_crashes and inventory" "$X/runner11.sh" "$OUT/k" K9-S; echo "NIGHT k done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
