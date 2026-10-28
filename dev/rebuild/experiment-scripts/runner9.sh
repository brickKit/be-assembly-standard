#!/bin/bash
# Step 9 (step9-plan.md): every cell given, in order, unattended. Per cell:
#   empty: brought up without seed data (SEED=0: installed and claimed only), idle 10 min, down;
#   full:  brought up with seed data (twice) and L3, the baseline data, the expectation and scope scenarios, the result
#          digest compared within the batch (REF below), then idle 10 min, warmup 5 min and the 7/s mix for 15 min, down.
# Every stage writes BEGIN/END to <out>/status.log; a failing stage is recorded and the cell goes on where it can (a
# failed bring-up skips the rest of that segment). The power mode is recorded per cell. CONF points at a snapshot of
# the conformance tools (cell-chain.sh). Run it under systemd-inhibit so the machine does not sleep.
# Step 10 option (step10-plan.md): RATE2 (and USERS2) adds a second mix on the same cell after the first.
# Usage: runner9.sh <out> <cell>...
set -u
OUT=$(realpath -m "$1"); shift
R=/home/zhijie/Desktop/github/be-assembly-standard; CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
IDLE=${IDLE:-600}; WARMUP=${WARMUP:-300}; SECONDS_=${SECONDS_:-900}; RATE=${RATE:-7}; USERS=${USERS:-20}
# the result digest every cell must match: by default the batch's first cell's own (REF=first), so cells are compared
# within one batch; a fixed reference made on another day can differ, since the seeds are relative to today (the
# currency seed's rates on the weekdays of the last 60 days: step10-plan 5.3). REF=<digest.json> compares with that file.
REF=${REF:-first}; REF_NAME=$(basename "$(dirname "$REF")")
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
down() {  # down <cell dir>: the cell's own down, then whatever an engine still holds
  # the L row's port forwarder first: cell-chain.sh starts it as its own process group and keeps the leader's PID
  # outside the cell, since brickkit down clears .brickkit/
  local f="${XDG_RUNTIME_DIR:-/tmp}/be-cell-forward-$(basename "$1").pid"
  [ -f "$f" ] && { kill -- -"$(cat "$f")" 2>/dev/null; rm -f "$f"; }
  (cd "$1" && brickkit down) || true
  # a mode: local session (L, LD, LP), which brickkit down does not reach: stopped by its PID (cells/localrun.py)
  (cd "$CONF" && uv run python -m cells.localrun down "$1") || true
  docker rm -f be-pgbouncer >/dev/null 2>&1 || true  # a pooler cell's PgBouncer (cell-chain.sh starts it)
}
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl for the K row
cluster() {  # cluster <on|off>: the minikube node (profile bek) runs only during the K row's cells
  local up=0; minikube -p bek status >/dev/null 2>&1 && up=1
  # started, and ready only once a pod resolves the base resources' host (cluster-on.sh)
  if [ "$1" = on ] && [ $up = 0 ]; then log "CLUSTER start"; "$R/dev/rebuild/experiment-scripts/cluster-on.sh" "$OUT/cluster.log" \
    >> "$OUT/cluster.log" 2>&1 || log "CLUSTER start FAILED"; fi
  if [ "$1" = off ] && [ $up = 1 ]; then log "CLUSTER stop"; minikube -p bek stop >> "$OUT/cluster.log" 2>&1; fi
}
log "START rate=$RATE users=$USERS rate2=${RATE2:-} users2=${USERS2:-} ref=$REF idle=$IDLE warmup=$WARMUP seconds=$SECONDS_ conf=$CONF"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; mkdir -p "$OUT/$CELL"
  ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); [ "$ROW" = K ] && cluster on || cluster off
  log "CELL $CELL power=$(powerprofilesctl get)"
  # empty
  if stage "$CELL" empty-up env KEEP_UP=1 SEED=0 "$R/dev/rebuild/experiment-scripts/cell-chain.sh" "$CELL" "$OUT/$CELL/empty-up"; then
    stage "$CELL" empty-idle bash -c "cd $CONF && uv run python -m cells chain $D $OUT/$CELL/empty --idle $IDLE" \
      || log "CELL $CELL FAILED empty-idle"
  else
    log "CELL $CELL FAILED empty-up"
  fi
  stage "$CELL" empty-down down "$D"
  # full
  if ! stage "$CELL" bring-up env KEEP_UP=1 "$R/dev/rebuild/experiment-scripts/cell-chain.sh" "$CELL" "$OUT/$CELL/bring-up"; then
    log "CELL $CELL FAILED bring-up"; stage "$CELL" down down "$D"; continue; fi
  if ! stage "$CELL" baseline bash -c "cd $CONF && uv run python -m cells baseline $D $OUT/$CELL/world.json"; then
    log "CELL $CELL FAILED baseline"; stage "$CELL" down down "$D"; continue; fi
  stage "$CELL" scenarios bash -c "cd $CONF && BE_ACC_CELL=$D uv run pytest -q scenarios/test_expectations.py scenarios/test_scope.py" \
    || log "CELL $CELL FAILED scenarios"
  if stage "$CELL" digest bash -c "cd $CONF && uv run python -m cells digest $D $OUT/$CELL/digest.json"; then
    if [ "$REF" = first ]; then REF=$OUT/$CELL/digest.json; REF_NAME=$CELL; log "CELL $CELL DIGEST is the reference"
    else
      stage "$CELL" compare bash -c "cd $CONF && uv run python -m cells compare $REF $OUT/$CELL/digest.json" \
        && log "CELL $CELL DIGEST same as $REF_NAME" || log "CELL $CELL DIGEST DIFFERS from $REF_NAME (compare.log)"
    fi
  else
    log "CELL $CELL FAILED digest"
  fi
  stage "$CELL" chain bash -c "cd $CONF && uv run python -m cells chain $D $OUT/$CELL/run --world $OUT/$CELL/world.json \
    --rate $RATE --users $USERS --idle $IDLE --warmup $WARMUP --seconds $SECONDS_" || log "CELL $CELL FAILED chain"
  # a second mix on the same cell and data when RATE2 is set (step 10, B5: twice the load): warmup and window as the first
  [ -n "${RATE2:-}" ] && { stage "$CELL" chain-2 bash -c "cd $CONF && uv run python -m cells chain $D $OUT/$CELL/run-2 \
    --world $OUT/$CELL/world.json --rate $RATE2 --users ${USERS2:-$USERS} --idle 0 --warmup $WARMUP --seconds $SECONDS_" \
    || log "CELL $CELL FAILED chain-2"; }
  stage "$CELL" down down "$D"
done
cluster off
log "ALL-DONE"
