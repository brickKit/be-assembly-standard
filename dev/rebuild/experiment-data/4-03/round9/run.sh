#!/bin/bash
# Round 9: the round 8 cells after P5.31 (campaign-round9.yaml), under the performance power profile; the profile before it is restored at the end.
source <scratch>/accenv.sh
echo $$ > <scratch>/round9/pid
restore() { powerprofilesctl set "$(cat <scratch>/round9/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> <scratch>/round9/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> <scratch>/round9/status.log
cd <repo>/tools/be-acceptance/conformance && uv run python -m cells campaign <repo>/dev/rebuild/experiment-cells/campaign-round9.yaml <scratch>/round9/measure > <scratch>/round9/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> <scratch>/round9/status.log
