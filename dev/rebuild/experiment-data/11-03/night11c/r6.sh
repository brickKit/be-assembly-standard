#!/bin/bash
# round 6, a diagnosis: D9-H's split with SPLIT_SETTLE=0 (the L3 scenarios as soon as every component is ready, as in
# rounds 1 and 3), keeping each container's log, to see what answered `processing` in the seconds after ready
X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$1/r6"; echo $$ > "$1/r6/night.pid"; echo "NIGHT split-diagnosis D9-H $(date -Is)" >> "$1/r6/night.log"
SPLIT_SETTLE=0 FAULTS=split "$X/runner11.sh" "$1/r6/d" D9-H; echo "NIGHT d done exit=$? $(date -Is)" >> "$1/r6/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$1/r6/night.log"
