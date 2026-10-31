#!/bin/bash
# round 3: D9-H's split again (ops11.sh now waits for every component's /readyz before the L3 scenarios), then
# night11c.sh's K9-H and K9-X
X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$1/r3"; echo "NIGHT split-again D9-H $(date -Is)" >> "$1/r3/night.log"
FAULTS=split "$X/runner11.sh" "$1/r3/d" D9-H; echo "NIGHT d done exit=$? $(date -Is)" >> "$1/r3/night.log"
exec "$X/night11c.sh" "$1" r3 K9-H K9-X
