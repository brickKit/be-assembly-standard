#!/bin/bash
# The D-S-pg relay at 200/s again, twice, under the performance power profile.
source <scratch>/accenv.sh
echo $$ > <scratch>/relaycheck/pid
restore() { powerprofilesctl set "$(cat <scratch>/relaycheck/power-before.txt)"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> <scratch>/relaycheck/status.log; }
trap restore EXIT
powerprofilesctl set performance
echo "POWER $(powerprofilesctl get) $(date -Is)" >> <scratch>/relaycheck/status.log
cd <repo>/tools/be-acceptance/conformance && uv run python -m cells campaign <repo>/dev/rebuild/experiment-cells/campaign-relay-check.yaml <scratch>/relaycheck/measure > <scratch>/relaycheck/campaign.log 2>&1
echo "END exit=$? $(date -Is)" >> <scratch>/relaycheck/status.log
