#!/bin/bash
# Round 10: the subscription concurrency through the deployment's key (campaign-round10.yaml), under the performance power profile; the profile before it is restored at the end.
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
echo $$ > /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/pid
restore() { powerprofilesctl set "$(cat /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/status.log
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance && uv run python -m cells campaign /home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-cells/campaign-round10.yaml /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/measure > /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round10/status.log
