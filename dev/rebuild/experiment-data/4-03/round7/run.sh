#!/bin/bash
# Round 7: the calls of D-H2 and D-X, the subscription knob, the PostgreSQL queue after P6.30 (campaign-round7.yaml), under the performance power profile; the profile before it is restored at the end.
source <scratch>/accenv.sh
echo $$ > <scratch>/round7/pid
restore() { powerprofilesctl set "$(cat <scratch>/round7/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> <scratch>/round7/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> <scratch>/round7/status.log
cd <repo>/tools/be-acceptance/conformance && uv run python -m cells campaign <repo>/dev/rebuild/experiment-cells/campaign-round7.yaml <scratch>/round7/measure > <scratch>/round7/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> <scratch>/round7/status.log
