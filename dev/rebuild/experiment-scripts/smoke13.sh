#!/bin/bash
# Step 13, step 3 (step13-plan.md): suite E's smoke. Each cell brought up from nothing with its seed data (twice) and
# the L3 scenarios (cell-chain.sh), no load and no measurement; before it goes down, every container's or pod's log is
# saved (packed) and counted per replica (replica-counts.sh). The D row first (D13-E1, D13-E5 and D13-E7 passed as
# step 2's trials on the same tools), then the K row with the minikube node on, which publishes the components' host
# ports the D row's cells bind too (smoke12.sh), stopped at the end. smoke.log gets the outermost mark SMOKE13 ALL-DONE.
# Usage: smoke13.sh <out> [cell...]   (default: D13-E2 D13-E4 D13-E6a D13-E6b K13-E1 K13-E2)
set -u
OUT=$(realpath -m "$1"); shift
R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
export PATH=$X/bin:$PATH  # kubectl for the K row
CELLS=("$@"); [ ${#CELLS[@]} -gt 0 ] || CELLS=(D13-E2 D13-E4 D13-E6a D13-E6b K13-E1 K13-E2)
mkdir -p "$OUT"; echo $$ > "$OUT/smoke.pid"; LOG=$OUT/smoke.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
kube() { kubectl --context bek "$@"; }
logs() {  # as runner13.sh
  local D=$1 O=$2 ROW=$3 ns=${1##*/}; ns=${ns,,}; mkdir -p "$O"
  case $ROW in
    K) for p in $(kube -n "$ns" get pods -o name 2>/dev/null); do kube -n "$ns" logs "$p" --all-containers > "$O/${p#pod/}.log" 2>&1; done ;;
    *) for n in $(docker ps -a --filter "label=com.docker.compose.project=brickkit-$ns" --format '{{.Names}}'); do docker logs "$n" > "$O/$n.log" 2>&1; done ;;
  esac
}
say "SMOKE13 START cells=${CELLS[*]} conf=$CONF brickkit=$(brickkit --version | head -1)"
for CELL in "${CELLS[@]}"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; O=$OUT/$CELL; mkdir -p "$O"
  ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml")
  if [ "$ROW" = K ] && ! minikube -p bek status >/dev/null 2>&1; then
    if "$X/cluster-on.sh" "$OUT/cluster-on.log" > "$OUT/cluster-on.out" 2>&1; then say "SMOKE13 cluster on"; else say "SMOKE13 FAILED cluster-on"; fi
  fi
  if KEEP_UP=1 "$X/cell-chain.sh" "$CELL" "$O/bring-up" > "$O/bring-up.log" 2>&1; then say "CELL $CELL passed"
  else say "CELL $CELL FAILED $(grep -h 'END exit=[1-9]' "$O/bring-up/status.log" | tail -1)"; fi
  logs "$D" "$O/logs" "$ROW"
  bash "$X/replica-counts.sh" "$O/logs" "$O/replica-counts.txt" > /dev/null
  find "$O/logs" -name '*.log' -size +256k -exec gzip -9 {} +
  { (cd "$CONF" && uv run python -m cells front down "$D"); (cd "$D" && brickkit down); docker rm -fv be-postgres-2; } > "$O/down.log" 2>&1
  say "CELL $CELL down"
done
minikube -p bek status >/dev/null 2>&1 && { minikube -p bek stop > "$OUT/cluster-off.log" 2>&1; say "SMOKE13 cluster off exit=$?"; }
say "SMOKE13 cells: $(grep -c ' passed ' "$LOG") passed, $(grep -c ' FAILED ' "$LOG") failed"
say "SMOKE13 ALL-DONE"
