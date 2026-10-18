#!/bin/bash
# Narrowed round 5: stop the campaign when it reaches D-H2 (keep the base cells, D-S and D-H1), then bring D-H2 down.
P=$(cat <scratch>/round5/pid)
until grep -q '^== run 1 D-H2 ' <scratch>/round5/campaign.log; do kill -0 $P 2>/dev/null || exit 0; sleep 5; done
kill -TERM -- -$P; sleep 10
source <scratch>/accenv.sh; cd <repo>/dev/rebuild/experiment-cells/D-H2 && brickkit down > <scratch>/round5/down-h2.log 2>&1
echo "END narrowed after D-H1 $(date -Is)" >> <scratch>/round5/status.log
