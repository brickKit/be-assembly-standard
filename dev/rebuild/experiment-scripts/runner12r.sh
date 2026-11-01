#!/bin/bash
# Step 12 (step12-plan.md 9.1, item 2), suite D on the other rows: for each cell, bring it up from nothing (cell-chain.sh,
# SEED=0) and run the suite D tests that fit it, keep the outputs and the logs, bring it down on its own engine.
#   - a cell without `also:` (V4): compat/test_pairs.py;
#   - a cell with `also:` (V1, the P and K rows): the expand tests, a second brickkit up (every version's migration
#     again), the older version's migration run again (V1_PHASE=again; on K the second up runs every migration Job
#     again and this script checks each completed). On K the older version has no published host port: kubectl
#     port-forward gives it host port 18610 + n, as the other rows' `also` port.
# A failing test is a result, not a stop. status.log gets one line per stage and the outermost mark R12R ALL-DONE.
# Usage: runner12r.sh <out> <cell>...   (CONF: a snapshot of the conformance tools)
set -u
OUT=$(realpath -m "$1"); shift; R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
export PATH=$X/bin:$PATH  # kubectl for the K row
. "$X/accenv.sh"
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"; LOG=$OUT/status.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
kube() { kubectl --context bek "$@"; }
logs() {  # every container's, pod's or session's log of the cell, on its own engine
  local D=$1 O=$2 ROW=$3 ns=${1##*/}; ns=${ns,,}; mkdir -p "$O/logs"
  case $ROW in
    K) for p in $(kube -n "$ns" get pods -o name 2>/dev/null); do kube -n "$ns" logs "$p" --all-containers > "$O/logs/${p#pod/}.log" 2>&1; done ;;
    P|LP) for n in $(podman ps -a --filter "label=com.docker.compose.project=brickkit-$ns" --format '{{.Names}}'); do podman logs "$n" > "$O/logs/$n.log" 2>&1; done ;;
    *) for n in $(docker ps -a --filter "label=com.docker.compose.project=brickkit-$ns" --format '{{.Names}}'); do docker logs "$n" > "$O/logs/$n.log" 2>&1; done ;;
  esac
}
down() {  # brickkit down does not reach a mode: local session or its forwarder (cell-chain.sh does the same)
  local D=$1 f="${XDG_RUNTIME_DIR:-/tmp}/be-cell-forward-$(basename "$1").pid"
  (cd "$D" && brickkit down)
  (cd "$CONF" && uv run python -m cells.localrun down "$D") 2>/dev/null
  [ -f "$f" ] && { kill -- -"$(cat "$f")" 2>/dev/null; rm -f "$f"; }
  true
}
pytest_in() { (cd "$CONF" && BE_ACC_CELL=$1 uv run pytest -rA -s -q "${@:2}"); }
say "R12R START cells=$* conf=$CONF brickkit=$(brickkit --version | head -1)"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; O=$OUT/$CELL; mkdir -p "$O"
  ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); ns=${CELL,,}; PF=
  if ! SEED=0 KEEP_UP=1 "$X/cell-chain.sh" "$CELL" "$O/bring-up" > "$O/bring-up.log" 2>&1; then
    say "CELL $CELL FAILED bring-up $(grep -h 'END exit=[1-9]' "$O/bring-up/status.log" | tail -1)"
  elif grep -q '^also:' "$D/cell.yaml"; then
    if [ "$ROW" = K ]; then  # the older version's Service to host port 18610 + n
      ref=$(sed -n 's/^also: *\[\(.*\)\]/\1/p' "$D/cell.yaml"); svc=$(echo "${ref%@*}-${ref#*@}" | tr '/.' '--')
      port=$(cd "$CONF" && uv run python -c "import sys; from cells.spec import PORTS; print(PORTS[sys.argv[1]][0])" "${ref%@*}")
      name=$(kube -n "$ns" get svc -o name | sed 's|service/||' | grep "^$svc" | head -1)
      kube -n "$ns" port-forward "svc/$name" "$((10000 + port + 10)):$port" > "$O/port-forward.log" 2>&1 & PF=$!
      sleep 3; say "CELL $CELL PORT-FORWARD svc/$name $((10000 + port + 10)):$port pid=$PF"
    fi
    pytest_in "$D" compat/test_v1.py > "$O/expand.log" 2>&1; say "CELL $CELL EXPAND exit=$? $(tail -1 "$O/expand.log")"
    (cd "$D" && brickkit up) > "$O/up-again.log" 2>&1; say "CELL $CELL UP-AGAIN exit=$?"
    if [ "$ROW" = K ]; then
      kube -n "$ns" get jobs -o custom-columns=NAME:.metadata.name,SUCCEEDED:.status.succeeded,FAILED:.status.failed,CREATED:.metadata.creationTimestamp > "$O/jobs.txt" 2>&1
      say "CELL $CELL JOBS $(awk 'NR>1 && $2!="1"{bad++} NR>1{n++} END{printf "%d jobs, %d not succeeded", n, bad}' "$O/jobs.txt")"
    fi
    V1_PHASE=again pytest_in "$D" compat/test_v1.py > "$O/again.log" 2>&1; say "CELL $CELL AGAIN exit=$? $(tail -1 "$O/again.log")"
  else
    pytest_in "$D" compat/test_pairs.py > "$O/tests.log" 2>&1; say "CELL $CELL TESTS exit=$? $(tail -1 "$O/tests.log")"
  fi
  [ -n "$PF" ] && kill "$PF" 2>/dev/null
  logs "$D" "$O" "$ROW"
  down "$D" > "$O/down.log" 2>&1
  say "CELL $CELL DONE"
done
say "R12R ALL-DONE"
