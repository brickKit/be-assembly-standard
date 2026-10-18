#!/bin/bash
# Re-runs every test related to the recent changes (protocol alpha.4, SDKs, probes, shells, BrickKit v1.8.2), then
# profiles three deployed cells and measures every D cell at fixed rates. Stages write BEGIN/END lines to status.log;
# each stage's output goes to its own log. A failing stage does not stop the next (the watcher reports it at once).
set -u
OUT=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; T=$R/tools
mkdir -p "$OUT/logs" "$OUT/profile"; echo $$ > "$OUT/pid"
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
CELLS=$R/dev/rebuild/experiment-cells; CONF=$T/be-acceptance/conformance
N=11; I=0
stage() {  # stage <name> <command...>
  I=$((I+1)); local name=$1; shift; local t0=$(date +%s)
  echo "STAGE $I/$N $name BEGIN $(date -Is)" >> "$OUT/status.log"
  ( "$@" ) > "$OUT/logs/$I-$name.log" 2>&1; local rc=$?
  echo "STAGE $I/$N $name END exit=$rc secs=$(( $(date +%s) - t0 ))" >> "$OUT/status.log"
}
down_cells() {
  for p in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep '^brickkit-d-' | sort -u); do
    docker compose -p "$p" down --remove-orphans; done
}
profile_cell() {  # create, prepare, build, up, profile, down one cell; reports kept under $OUT/profile/<cell>
  local d=$CELLS/$1 rc=0
  down_cells
  cd "$CONF" && uv run python -m cells create "$d" && uv run python -m cells prepare "$d" || return 1
  cd "$d" && brickkit build && brickkit up || { brickkit down; return 1; }
  cd "$CONF" && uv run python -m cells profile "$d"; rc=$?
  cd "$d" && brickkit down
  rm -rf "${OUT:?}/profile/$1"; mv "$d/reports" "$OUT/profile/$1"
  return $rc
}
echo "START $(date -Is)" >> "$OUT/status.log"
stage protocol bash -c "cd $T/be-protocol && go vet ./... && go test -count=1 ./..."
stage sdk-go-unit bash -c "cd $T/be-sdk-go && go vet ./... && go test -count=1 -v ./... "
stage sdk-go-integration bash -c "cd $T/be-sdk-go && go test -count=1 -p 1 -v -tags integration ./..."
stage sdk-py-unit bash -c "cd $T/be-sdk-python && python3 -I scripts/protocol.py check && uv run pytest -q --durations=15"
stage sdk-py-integration bash -c "cd $T/be-sdk-python && uv run pytest -q -m integration --durations=15"
stage acceptance bash -c "cd $CONF && uv run pytest -q --durations=15 && cd $T/be-acceptance/load && go test -count=1 -v ./... && cd $T/be-acceptance/probes/go && go vet ./... && go test -count=1 ./... && python3 $T/be-acceptance/probes/variants.py --check"
stage shells bash -c "set -e; for s in go-core go-infra; do cd $R/shell/be/\$s && go vet ./... && go test -count=1 -v ./... && brickkit lint; done; cd $R/shell/be/py-render && uv run pytest -q && brickkit lint"
stage profile-D-S profile_cell D-S
stage profile-D-X profile_cell D-X
stage profile-D-H2 profile_cell D-H2
stage measure-all bash -c "cd $CONF && uv run python -m cells campaign $CELLS/campaign-check.yaml $OUT/measure"
down_cells >> "$OUT/logs/cleanup.log" 2>&1
echo "END $(date -Is)" >> "$OUT/status.log"
