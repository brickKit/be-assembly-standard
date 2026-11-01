#!/bin/bash
# round 4: D9-H's split once more, ops11.sh now also waiting for every outbound circuit breaker to close before the
# L3 scenarios, and keeping each component's be_outbound_* lines from when it was ready
X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$1/r4"; echo $$ > "$1/r4/night.pid"; echo "NIGHT split-again D9-H $(date -Is)" >> "$1/r4/night.log"
FAULTS=split "$X/runner11.sh" "$1/r4/d" D9-H; echo "NIGHT d done exit=$? $(date -Is)" >> "$1/r4/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$1/r4/night.log"
