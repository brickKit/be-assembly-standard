#!/bin/bash
# Step 9, the probes on the other rows (experiment plan, suite A items 3 and 4): every probe cell given, in order,
# unattended. Per cell: brought up from nothing (cell-chain.sh, SEED=0: the probes need no seed data), then
# `cells run`: idle for IDLE seconds (a base-cost cell has no chain, so that is all), then every edge of the chain at
# every operation in OPS and load in LOADS (WARMUP and SECONDS_ each), then down. The same tools as the D row's
# campaign (step 4), with the row's own bring-up and sampler (containers, pods or processes).
# Every stage writes BEGIN/END to <out>/status.log; a failed cell is recorded and the run goes on. The power mode is
# recorded per cell. CONF points at a snapshot of the conformance tools. Run it under systemd-inhibit.
# Usage: probe9.sh <out> <cell>...
set -u
OUT=$(realpath -m "$1"); shift
R=/home/zhijie/Desktop/github/be-assembly-standard; CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
IDLE=${IDLE:-600}; WARMUP=${WARMUP:-10}; SECONDS_=${SECONDS_:-30}
OPS=${OPS:-echo-1k-grpc,echo-1k-http,echo-60k-grpc,echo-60k-http,work-grpc,work-http,write,relay,big-event}
LOADS=${LOADS:-200}
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
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
down() {  # the same as runner9.sh: the local row's forwarder, the cell's own down, a mode: local session by its PID
  local f="${XDG_RUNTIME_DIR:-/tmp}/be-cell-forward-$(basename "$1").pid"
  [ -f "$f" ] && { kill -- -"$(cat "$f")" 2>/dev/null; rm -f "$f"; }
  (cd "$1" && brickkit down) || true
  (cd "$CONF" && uv run python -m cells.localrun down "$1") || true
}
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl for the K row
cluster() {  # cluster <on|off>: the minikube node (profile bek) runs only during the K row's cells
  local up=0; minikube -p bek status >/dev/null 2>&1 && up=1
  # started, and ready only once a pod resolves the base resources' host (cluster-on.sh)
  if [ "$1" = on ] && [ $up = 0 ]; then log "CLUSTER start"; "$R/dev/rebuild/experiment-scripts/cluster-on.sh" "$OUT/cluster.log" \
    >> "$OUT/cluster.log" 2>&1 || log "CLUSTER start FAILED"; fi
  if [ "$1" = off ] && [ $up = 1 ]; then log "CLUSTER stop"; minikube -p bek stop >> "$OUT/cluster.log" 2>&1; fi
}
log "START idle=$IDLE warmup=$WARMUP seconds=$SECONDS_ ops=$OPS loads=$LOADS conf=$CONF"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; mkdir -p "$OUT/$CELL"
  ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); [ "$ROW" = K ] && cluster on || cluster off
  log "CELL $CELL power=$(powerprofilesctl get)"
  if stage "$CELL" up env KEEP_UP=1 SEED=0 "$R/dev/rebuild/experiment-scripts/cell-chain.sh" "$CELL" "$OUT/$CELL/up"; then
    stage "$CELL" run bash -c "cd $CONF && uv run python -m cells run $D $OUT/run1/$CELL --ops $OPS --loads $LOADS \
      --idle $IDLE --warmup $WARMUP --seconds $SECONDS_" || log "CELL $CELL FAILED run"
  else
    log "CELL $CELL FAILED up"
  fi
  stage "$CELL" down down "$D"
done
cluster off
log "ALL-DONE"
