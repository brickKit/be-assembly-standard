#!/bin/bash
# Round 8: D-S, D-S-pg and D-S-pg-c4 after P5.30 and one wake per message (campaign-round8.yaml), under the performance power profile; the profile before it is restored at the end.
source <scratch>/accenv.sh
echo $$ > <scratch>/round8/pid
restore() { powerprofilesctl set "$(cat <scratch>/round8/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> <scratch>/round8/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> <scratch>/round8/status.log
cd <repo>/tools/be-acceptance/conformance && uv run python -m cells campaign <repo>/dev/rebuild/experiment-cells/campaign-round8.yaml <scratch>/round8/measure > <scratch>/round8/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> <scratch>/round8/status.log
