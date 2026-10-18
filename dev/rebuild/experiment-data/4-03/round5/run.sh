#!/bin/bash
# Round 5: the full-cell check (campaign-check.yaml, 1 run, short windows) as the D-row result, under the performance power profile; the profile before it is restored at the end.
source <scratch>/accenv.sh
echo $$ > <scratch>/round5/pid
restore() { powerprofilesctl set "$(cat <scratch>/round5/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> <scratch>/round5/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> <scratch>/round5/status.log
cd <repo>/tools/be-acceptance/conformance && uv run python -m cells campaign <repo>/dev/rebuild/experiment-cells/campaign-check.yaml <scratch>/round5/measure > <scratch>/round5/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> <scratch>/round5/status.log
