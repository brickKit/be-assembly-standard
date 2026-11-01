#!/bin/bash
# Step 12, suite D V1 again on D12-V1b (SDKs with P5.32): up with the default version and the older one side by side,
# the expand tests; brickkit up again (every version's migration runs again: the older one meets the newer schema);
# the older version's migration run again by hand. Keeps the outputs and every container's log; the cell goes down.
# Usage: v1b.sh <out>   (CONF: a snapshot of the conformance tools)
set -u
OUT=$(realpath -m "$1"); R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF; D=$R/dev/rebuild/experiment-cells/D12-V1b
. "$X/accenv.sh"
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"; LOG=$OUT/status.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
say "START brickkit=$(brickkit --version | head -1)"
if SEED=0 KEEP_UP=1 "$X/cell-chain.sh" D12-V1b "$OUT/bring-up" > "$OUT/bring-up.log" 2>&1; then
  (cd "$CONF" && BE_ACC_CELL=$D V1_PHASE=expand uv run pytest -rA -s -q compat/test_v1.py > "$OUT/expand.log" 2>&1)
  say "EXPAND exit=$? $(tail -1 "$OUT/expand.log")"
  (cd "$D" && brickkit up) > "$OUT/up-again.log" 2>&1; say "UP-AGAIN exit=$?"
  docker ps -a --filter "label=com.docker.compose.project=brickkit-d12-v1b" --format '{{.Names}} {{.Status}}' > "$OUT/containers.txt"
  (cd "$CONF" && BE_ACC_CELL=$D V1_PHASE=again uv run pytest -rA -s -q compat/test_v1.py > "$OUT/again.log" 2>&1)
  say "AGAIN exit=$? $(tail -1 "$OUT/again.log")"
else
  say "FAILED bring-up"
fi
mkdir -p "$OUT/logs"
for n in $(docker ps -a --filter "label=com.docker.compose.project=brickkit-d12-v1b" --format '{{.Names}}'); do
  docker logs "$n" > "$OUT/logs/$n.log" 2>&1; done
(cd "$D" && brickkit down) > "$OUT/down.log" 2>&1
say "ALL-DONE"
