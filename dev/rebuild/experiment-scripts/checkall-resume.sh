#!/bin/bash
# Resumes stage 11 of checkall.sh (finished cells are kept) after the port band fix.
set -u
OUT=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; CONF=$R/tools/be-acceptance/conformance; CELLS=$R/dev/rebuild/experiment-cells
echo $$ > "$OUT/pid"
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
t0=$(date +%s)
echo "STAGE 11/11 measure-all BEGIN $(date -Is) (resumed)" >> "$OUT/status.log"
( cd "$CONF" && uv run python -m cells campaign "$CELLS/campaign-check.yaml" "$OUT/measure" ) >> "$OUT/logs/11-measure-all.log" 2>&1
echo "STAGE 11/11 measure-all END exit=$? secs=$(( $(date +%s) - t0 ))" >> "$OUT/status.log"
for p in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep '^brickkit-d-' | sort -u); do docker compose -p "$p" down --remove-orphans; done >> "$OUT/logs/cleanup.log" 2>&1
echo "END $(date -Is)" >> "$OUT/status.log"
