#!/bin/bash
# Round 10 reproduction; records and restores the power profile itself.
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
O=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/repro
before=$(powerprofilesctl get)
trap 'powerprofilesctl set "$before"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> $O/status.log' EXIT
powerprofilesctl set performance; echo "POWER $before -> $(powerprofilesctl get) $(date -Is)" >> $O/status.log
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance && uv run python -m cells campaign /home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-cells/campaign-round10-repro.yaml $O/measure > $O/campaign.log 2>&1
echo "END exit=$? results=$(find $O/measure -name result.json | wc -l) $(date -Is)" >> $O/status.log
