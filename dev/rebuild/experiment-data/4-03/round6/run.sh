#!/bin/bash
# Round 6: the event paths of the eight load cells after P7.21 (campaign-events.yaml) under the performance power profile; the profile before it is restored at the end.
source <scratch>/accenv.sh
echo $$ > <scratch>/round6/pid
restore() { powerprofilesctl set "$(cat <scratch>/round6/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> <scratch>/round6/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> <scratch>/round6/status.log
cd <repo>/tools/be-acceptance/conformance && uv run python -m cells campaign <repo>/dev/rebuild/experiment-cells/campaign-events.yaml <scratch>/round6/measure > <scratch>/round6/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> <scratch>/round6/status.log
