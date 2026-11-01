#!/bin/bash
# round 5: D9-H's split once more, ops11.sh waiting until every caller reaches its dependencies again (breakers
# closed, no new failed attempt for 3 s) before the L3 scenarios; round 4 misread a Python gauge's 0.0 as open
X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$1/r5"; echo $$ > "$1/r5/night.pid"; echo "NIGHT split-again D9-H $(date -Is)" >> "$1/r5/night.log"
FAULTS=split "$X/runner11.sh" "$1/r5/d" D9-H; echo "NIGHT d done exit=$? $(date -Is)" >> "$1/r5/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$1/r5/night.log"
