#!/bin/bash
# Step 8 rounds (step8-plan.md): for each cell in the order given, bring it up from empty schemas (cell-chain.sh:
# create, prepare, build, up, secure, seed twice, L3), build the baseline data, then
#   correctness: the expectations and scope scenarios again, and the result digest once settled;
#   perf:        the measured run — idle, warmup, the mixed load — with the sampler (cells chain);
# then take the cell down. Every stage writes BEGIN/END to <out>/status.log; a failing cell is recorded and the round
# goes on with the next one. The power mode is recorded at the start of each cell (the user keeps it on performance).
# Usage: round8.sh <correctness|perf> <out> <cell>... (e.g. round8.sh perf out D8-S D8-H D8-X)
set -u
MODE=$1; OUT=$(realpath -m "$2"); shift 2
R=/home/zhijie/Desktop/github/be-assembly-standard; CONF=$R/tools/be-acceptance/conformance
RATE=${RATE:-7}; USERS=${USERS:-20}; IDLE=${IDLE:-600}; WARMUP=${WARMUP:-300}; SECONDS_=${SECONDS_:-900}
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export BE_ACC_IAM_TEST_PASSWORD; BE_ACC_IAM_TEST_PASSWORD=$(envval IAM_TEST_PASSWORD)
export BE_ACC_NATS_URL=nats://localhost:4222
export BE_ACC_PG_ADMIN; BE_ACC_PG_ADMIN="postgres://postgres:$(envval POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
log() { echo "$* $(date -Is)" >> "$OUT/status.log"; }
stage() {  # stage <cell> <name> <command...>; returns the command's status
  local cell=$1 name=$2; shift 2; local t0; t0=$(date +%s)
  log "STAGE $cell $name BEGIN"
  ( "$@" ) > "$OUT/$cell/$name.log" 2>&1; local rc=$?
  log "STAGE $cell $name END exit=$rc secs=$(( $(date +%s) - t0 ))"
  return $rc
}
log "START $MODE rate=$RATE users=$USERS idle=$IDLE warmup=$WARMUP seconds=$SECONDS_"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; mkdir -p "$OUT/$CELL"
  log "CELL $CELL power=$(powerprofilesctl get)"
  if ! stage "$CELL" bring-up env KEEP_UP=1 "$R/dev/rebuild/experiment-scripts/cell-chain.sh" "$CELL" "$OUT/$CELL/bring-up"; then
    log "CELL $CELL FAILED bring-up"; continue; fi
  if ! stage "$CELL" baseline bash -c "cd $CONF && uv run python -m cells baseline $D $OUT/$CELL/world.json"; then
    log "CELL $CELL FAILED baseline"; (cd "$D" && brickkit down) >/dev/null 2>&1; continue; fi
  if [ "$MODE" = correctness ]; then
    stage "$CELL" scenarios bash -c "cd $CONF && BE_ACC_CELL=$D uv run pytest -q scenarios/test_expectations.py scenarios/test_scope.py" \
      || log "CELL $CELL FAILED scenarios"
    stage "$CELL" digest bash -c "cd $CONF && uv run python -m cells digest $D $OUT/$CELL/digest.json" || log "CELL $CELL FAILED digest"
  else
    stage "$CELL" chain bash -c "cd $CONF && uv run python -m cells chain $D $OUT/$CELL/run --world $OUT/$CELL/world.json \
      --rate $RATE --users $USERS --idle $IDLE --warmup $WARMUP --seconds $SECONDS_" || log "CELL $CELL FAILED chain"
  fi
  stage "$CELL" down bash -c "cd $D && brickkit down"
done
log "ALL-DONE"
