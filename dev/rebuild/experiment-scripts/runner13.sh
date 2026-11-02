#!/bin/bash
# Step 13 (step13-plan.md), suite E: every cell given, in order, unattended. Per cell: brought up with seed data and
# the L3 scenarios (cell-chain.sh; a cell with replicas gets its front doors there), the baseline data and the mix's
# world, the invariants, then under the background load (the RATE/s mix, load -series) each step of STEPS in turn,
# each followed by the invariants; while the load runs, holders.py samples which process holds each running work item
# (every replica should appear). Then the load stops, the invariants once more, every container's, pod's or
# process's log is saved and counted per replica (replica-counts.sh) before the cell goes down: the logs go with it.
# STEPS, comma-separated: scenarios (the L3 scenarios again, under the load); faults:<pytest -k expression> (the
# fault tests, E3 and RS05/RS06 with replicas; what they measured goes to <cell>/faults.jsonl); e4 (out-of-order and
# repeated department events, compat/test_projection.py); e7 (the business database rolled back to T, e7_rollback.py:
# the load runs on until the cell is frozen, then stops; the cell stays frozen, so it is the last step and no
# invariants follow it); sh:<command>
# (a command of this directory). Every stage writes BEGIN/END to <out>/status.log; a failing step or invariant is recorded and the next
# goes on. CONF may point at a snapshot of the conformance tools (cell-chain.sh).
# Usage: runner13.sh <out> <cell>...
set -u
OUT=$(realpath -m "$1"); shift
R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
RATE=${RATE:-7}; USERS=${USERS:-20}; INV_WAIT=${INV_WAIT:-600}; STEPS=${STEPS:-scenarios}
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"
. "$X/accenv.sh"
export BE_ACC_IAM_TEST_PASSWORD; BE_ACC_IAM_TEST_PASSWORD=$(grep '^IAM_TEST_PASSWORD=' "$R/.env" | cut -d= -f2- | tr -d "\"'")
export BE_ACC_NATS_URL=nats://localhost:4222  # the stream check of the invariants
export PATH=$X/bin:$PATH  # kubectl for the K row
log() { echo "$* $(date -Is)" >> "$OUT/status.log"; }
stage() {  # stage <cell> <name> <command...>; returns the command's status
  local cell=$1 name=$2; shift 2; local t0; t0=$(date +%s)
  log "STAGE $cell $name BEGIN"
  ( "$@" ) > "$OUT/$cell/$name.log" 2>&1; local rc=$?
  log "STAGE $cell $name END exit=$rc secs=$(( $(date +%s) - t0 ))"
  return $rc
}
kube() { kubectl --context bek "$@"; }
down() {
  local D=$1
  (cd "$CONF" && uv run python -m cells front down "$D")
  (cd "$D" && brickkit down)
  docker rm -fv be-postgres-2 >/dev/null 2>&1
  true
}
invariants() { stage "$1" "invariants-$2" bash -c "cd $CONF && uv run python -m cells invariants $3 $OUT/$1/invariants-$2.json $INV_WAIT" \
  && log "CELL $1 INVARIANTS $2 hold" || log "CELL $1 INVARIANTS $2 VIOLATED"; }
cluster() {  # the minikube node runs only for the K row's cells: it publishes the host ports the other rows bind
  local up=0; minikube -p bek status >/dev/null 2>&1 && up=1
  if [ "$1" = on ] && [ $up = 0 ]; then log "CLUSTER start"; "$X/cluster-on.sh" "$OUT/cluster.log" >> "$OUT/cluster.log" 2>&1 || log "CLUSTER start FAILED"; fi
  if [ "$1" = off ] && [ $up = 1 ]; then log "CLUSTER stop"; minikube -p bek stop >> "$OUT/cluster.log" 2>&1; fi
}
stop_bg() { for p in ${LPID:-} ${HPID:-}; do kill -INT "$p" 2>/dev/null && wait "$p" 2>/dev/null; done; LPID=; HPID=; }
trap 'stop_bg' EXIT
(cd "$CONF/../load" && go build -o "$OUT/load" .) || { log "FAILED load build"; exit 1; }
log "START rate=$RATE users=$USERS inv_wait=$INV_WAIT steps=$STEPS conf=$CONF brickkit=$(brickkit --version | head -1)"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; mkdir -p "$OUT/$CELL"
  ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); [ "$ROW" = K ] && cluster on || cluster off
  log "CELL $CELL power=$(powerprofilesctl get)"
  if ! stage "$CELL" bring-up env KEEP_UP=1 "$X/cell-chain.sh" "$CELL" "$OUT/$CELL/bring-up"; then
    log "CELL $CELL FAILED bring-up"; bash "$X/cell-logs.sh" "$D" "$OUT/$CELL/logs" "$ROW"; stage "$CELL" down down "$D"; continue; fi
  if ! stage "$CELL" baseline bash -c "cd $CONF && uv run python -m cells baseline $D $OUT/$CELL/world.json"; then
    log "CELL $CELL FAILED baseline"; bash "$X/cell-logs.sh" "$D" "$OUT/$CELL/logs" "$ROW"; stage "$CELL" down down "$D"; continue; fi
  invariants "$CELL" before "$D"
  (cd "$CONF" && PYTHONPATH=. exec uv run python "$X/holders.py" "$D" "$OUT/$CELL/holders.txt") \
    > "$OUT/$CELL/holders.log" 2>&1 & HPID=$!
  BE_LOAD_PASSWORD=$BE_ACC_IAM_TEST_PASSWORD setsid "$OUT/load" -mix "$OUT/$CELL/world.json" -rate "$RATE" -users "$USERS" \
    -warmup 60s -duration 6h -out "$OUT/$CELL/load.json" -series "$OUT/$CELL/series.json" \
    > "$OUT/$CELL/load.log" 2>&1 < /dev/null & LPID=$!
  log "CELL $CELL load pid=$LPID holders pid=$HPID"; sleep 120
  IFS=, read -ra LIST <<< "$STEPS"; n=0
  for S in "${LIST[@]}"; do
    n=$((n + 1))
    case $S in
      scenarios) stage "$CELL" "step-$n" bash -c "cd $CONF && BE_ACC_CELL=$D uv run pytest -rA -q scenarios" ;;
      faults:*) stage "$CELL" "step-$n" bash -c "cd $CONF && BE_ACC_CELL=$D BE_ACC_FAULT_LOG=$OUT/$CELL/faults.jsonl uv run pytest -rA -q faults -k '${S#faults:}'" ;;
      e4) stage "$CELL" "step-$n" bash -c "cd $CONF && BE_ACC_CELL=$D uv run pytest -rA -q compat/test_projection.py -k e4" ;;
      e7) stage "$CELL" "step-$n" bash -c "cd $CONF && PYTHONPATH=. uv run python $X/e7_rollback.py $D $OUT/$CELL/e7.json ${E7_AFTER:-120}" \
            && log "CELL $CELL STEP $n ($S) passed" || log "CELL $CELL STEP $n ($S) FAILED"
          stop_bg; log "CELL $CELL load and holders stopped after e7 (the cell is frozen)"
          continue ;;
      sh:*) stage "$CELL" "step-$n" bash -c "cd $X && ./${S#sh:}" ;;
      *) log "CELL $CELL STEP $n ($S) unknown"; false ;;
    esac && log "CELL $CELL STEP $n ($S) passed" || log "CELL $CELL STEP $n ($S) FAILED"
    invariants "$CELL" "$n" "$D"
    sleep 60
  done
  if [ -n "${LPID:-}" ]; then stop_bg; log "CELL $CELL load and holders stopped"; invariants "$CELL" after "$D"; fi
  bash "$X/cell-logs.sh" "$D" "$OUT/$CELL/logs" "$ROW"
  stage "$CELL" down down "$D"
done
[ -n "${KEEP_CLUSTER:-}" ] || cluster off
log "ALL-DONE"
