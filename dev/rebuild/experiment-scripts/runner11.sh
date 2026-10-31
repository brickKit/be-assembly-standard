#!/bin/bash
# Step 11 (step11-plan.md), suite C: every cell given, in order, unattended. Per cell: brought up with seed data
# (cell-chain.sh), the baseline data and the mix's world, the background load (the 7/s mix with a per-second series,
# load -series) for the whole cell, then each fault in turn (be-acceptance conformance/faults/test_faults.py), each
# followed by the cell-wide invariants (python -m cells invariants, waiting up to INV_WAIT seconds for the work behind
# the fault to run) and a quiet minute; then the load is stopped and the cell goes down. Every stage writes BEGIN/END
# to <out>/status.log; a failing fault or invariant is recorded and the next fault goes on. What each fault measured
# is in <out>/<cell>/faults.jsonl, what the load saw in <out>/<cell>/series.json. CONF points at a snapshot of the
# conformance tools (cell-chain.sh); run it under systemd-inhibit (night-wrap.sh).
# FAULTS picks and orders the faults, comma-separated: pytest -k expressions (R1, R2), or burst (R3), split (R5, the H
# and X cells only) and upgrade (R4, last: it changes the versions), which run ops11.sh; sh:<command> runs a command of
# this directory between faults (probes11.sh). The default is all of them.
# Usage: runner11.sh <out> <cell>...
set -u
OUT=$(realpath -m "$1"); shift
R=/home/zhijie/Desktop/github/be-assembly-standard; CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
RATE=${RATE:-7}; USERS=${USERS:-20}; INV_WAIT=${INV_WAIT:-600}
FAULTS=${FAULTS:-rs06,rs05,bl04,"process_crashes and sales","process_crashes and inventory","process_crashes and billing",rs18,authorization,database,burst,split,upgrade}
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export BE_ACC_IAM_TEST_PASSWORD; BE_ACC_IAM_TEST_PASSWORD=$(envval IAM_TEST_PASSWORD)
export BE_ACC_PG_ADMIN; BE_ACC_PG_ADMIN="postgres://postgres:$(envval POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
export BE_ACC_NATS_URL=nats://localhost:4222  # the stream check of the invariants (cells/invariants.py)
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl for the K row
log() { echo "$* $(date -Is)" >> "$OUT/status.log"; }
stage() {  # stage <cell> <name> <command...>; returns the command's status
  local cell=$1 name=$2; shift 2; local t0; t0=$(date +%s)
  log "STAGE $cell $name BEGIN"
  ( "$@" ) > "$OUT/$cell/$name.log" 2>&1; local rc=$?
  log "STAGE $cell $name END exit=$rc secs=$(( $(date +%s) - t0 ))"
  return $rc
}
cluster() {  # the minikube node runs only during the K row's cells (as runner9.sh)
  local up=0; minikube -p bek status >/dev/null 2>&1 && up=1
  if [ "$1" = on ] && [ $up = 0 ]; then log "CLUSTER start"; "$R/dev/rebuild/experiment-scripts/cluster-on.sh" "$OUT/cluster.log" \
    >> "$OUT/cluster.log" 2>&1 || log "CLUSTER start FAILED"; fi
  if [ "$1" = off ] && [ $up = 1 ]; then log "CLUSTER stop"; minikube -p bek stop >> "$OUT/cluster.log" 2>&1; fi
}
stop_load() { [ -n "${LPID:-}" ] && kill -INT "$LPID" 2>/dev/null && wait "$LPID" 2>/dev/null; LPID=; }
trap 'stop_load' EXIT
(cd "$CONF/../load" && go build -o "$OUT/load" .) || { log "FAILED load build"; exit 1; }
log "START rate=$RATE users=$USERS inv_wait=$INV_WAIT faults=$FAULTS conf=$CONF"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; mkdir -p "$OUT/$CELL"
  ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); [ "$ROW" = K ] && cluster on || cluster off
  log "CELL $CELL power=$(powerprofilesctl get)"
  if ! stage "$CELL" bring-up env KEEP_UP=1 "$R/dev/rebuild/experiment-scripts/cell-chain.sh" "$CELL" "$OUT/$CELL/bring-up"; then
    log "CELL $CELL FAILED bring-up"; stage "$CELL" down bash -c "cd $D && brickkit down"; continue; fi
  if ! stage "$CELL" baseline bash -c "cd $CONF && uv run python -m cells baseline $D $OUT/$CELL/world.json"; then
    log "CELL $CELL FAILED baseline"; stage "$CELL" down bash -c "cd $D && brickkit down"; continue; fi
  stage "$CELL" invariants-before bash -c "cd $CONF && uv run python -m cells invariants $D $OUT/$CELL/invariants-before.json $INV_WAIT" \
    || log "CELL $CELL INVARIANTS violated before any fault"
  # the background load for the whole cell; stopped (SIGINT) after the last fault, so its window is the faults'
  BE_LOAD_PASSWORD=$BE_ACC_IAM_TEST_PASSWORD setsid "$OUT/load" -mix "$OUT/$CELL/world.json" -rate "$RATE" -users "$USERS" \
    -warmup 60s -duration 6h -out "$OUT/$CELL/load.json" -series "$OUT/$CELL/series.json" \
    > "$OUT/$CELL/load.log" 2>&1 < /dev/null & LPID=$!
  log "CELL $CELL load pid=$LPID"; sleep 120
  IFS=, read -ra LIST <<< "$FAULTS"; n=0
  for F in "${LIST[@]}"; do
    n=$((n + 1)); name="fault-$n"
    case $F in
      split) grep -q '^alone:' "$D/cell.yaml" && ! grep -q 'be/go' "$D/cell.yaml" && { log "CELL $CELL FAULT $n ($F) not for an S cell"; continue; }
        ;&
      burst|upgrade) stage "$CELL" "$name" env CONF="$CONF" "$R/dev/rebuild/experiment-scripts/ops11.sh" "$F" "$CELL" "$OUT/$CELL/$F" ;;
      sh:*) stage "$CELL" "$name" bash -c "cd $R/dev/rebuild/experiment-scripts && ./${F#sh:}" ;;
      *) stage "$CELL" "$name" bash -c "cd $CONF && BE_ACC_CELL=$D BE_ACC_FAULT_LOG=$OUT/$CELL/faults.jsonl uv run pytest -q -x faults -k '$F'" ;;
    esac && log "CELL $CELL FAULT $n ($F) passed" || log "CELL $CELL FAULT $n ($F) FAILED"
    stage "$CELL" "invariants-$n" bash -c "cd $CONF && uv run python -m cells invariants $D $OUT/$CELL/invariants-$n.json $INV_WAIT" \
      && log "CELL $CELL INVARIANTS $n hold" || log "CELL $CELL INVARIANTS $n VIOLATED"
    sleep 60
  done
  stop_load; log "CELL $CELL load stopped"
  stage "$CELL" down bash -c "cd $D && brickkit down"
done
[ -n "${KEEP_CLUSTER:-}" ] || cluster off
log "ALL-DONE"
