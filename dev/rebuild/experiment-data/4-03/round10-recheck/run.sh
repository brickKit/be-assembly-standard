#!/bin/bash
# Round 10 recheck: D-S-pg-c4 big events only, under the performance power profile.
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
echo $$ > /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/pid
restore() { powerprofilesctl set "$(cat /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/status.log
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance && uv run python -m cells campaign /home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-cells/campaign-round10-recheck.yaml /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/measure > /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10b/status.log
