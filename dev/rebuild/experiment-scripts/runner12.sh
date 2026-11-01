#!/bin/bash
# Step 12 (step12-plan.md section 5.1), suite D: for each cell, bring it up from nothing (cell-chain.sh; SEED=0 for the
# probe cells, which have no seed data), run the conformance tools' suite D tests against it (TESTS, a path under
# conformance/, default compat), keep the test output and every container's log, then bring the cell down. A failing
# test is a result, not a stop: the next cell still runs. status.log gets one line per stage.
# Usage: runner12.sh <out> <cell>...   (CONF: a snapshot of the conformance tools)
set -u
OUT=$(realpath -m "$1"); shift; R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF; TESTS=${TESTS:-compat}
. "$X/accenv.sh"  # the tests reach the base resources (BE_ACC_PG_ADMIN, BE_ACC_NATS_URL, ...)
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"; LOG=$OUT/status.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
say "START cells=$* tests=$TESTS conf=$CONF brickkit=$(brickkit --version | head -1)"
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; O=$OUT/$CELL; mkdir -p "$O"
  SEED=0; grep -q 'infra/iam-casdoor' "$D/cell.yaml" && SEED=1
  if ! SEED=$SEED KEEP_UP=1 "$X/cell-chain.sh" "$CELL" "$O/bring-up" > "$O/bring-up.log" 2>&1; then
    say "CELL $CELL FAILED bring-up"
  else
    (cd "$CONF" && BE_ACC_CELL=$D uv run pytest -rA -q "$TESTS" > "$O/tests.log" 2>&1); rc=$?
    say "CELL $CELL TESTS exit=$rc $(tail -1 "$O/tests.log")"
  fi
  mkdir -p "$O/logs"
  for n in $(docker ps -a --filter "label=com.docker.compose.project=brickkit-${CELL,,}" --format '{{.Names}}'); do
    docker logs "$n" > "$O/logs/$n.log" 2>&1; done
  (cd "$D" && brickkit down) > "$O/down.log" 2>&1
  say "CELL $CELL DONE"
done
say "ALL-DONE"
