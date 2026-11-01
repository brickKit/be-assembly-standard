#!/bin/bash
# Step 12, suite D V1 (step12-plan.md section 5.1) on D12-V1: up with the default version (expand migration) and the
# older one side by side, the expand tests; then the default moves to the contract migration's version while the older
# one keeps running (brickkit upgrade, build, up: only the changed service is recreated), the contract tests. Keeps the
# test output, the three-layer files after each phase and every container's log; the cell goes down at the end.
# Usage: v1.sh <out> [<contract version>]   (CONF: a snapshot of the conformance tools)
set -u
OUT=$(realpath -m "$1"); NEXT=${2:-3.2.24}; R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF; D=$R/dev/rebuild/experiment-cells/D12-V1
. "$X/accenv.sh"  # brickkit upgrade and up resolve the cell config's ${BE_ACC_*} references
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"; LOG=$OUT/status.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
keep() { mkdir -p "$OUT/$1"; cp "$D/brickkit.yaml" "$D/deploy.yaml" "$OUT/$1/"; docker ps -a --filter "label=com.docker.compose.project=brickkit-d12-v1" --format '{{.Names}} {{.Status}}' > "$OUT/$1/containers.txt"; }
say "START next=$NEXT brickkit=$(brickkit --version | head -1)"
if SEED=0 KEEP_UP=1 "$X/cell-chain.sh" D12-V1 "$OUT/bring-up" > "$OUT/bring-up.log" 2>&1; then
  keep expand
  (cd "$CONF" && BE_ACC_CELL=$D V1_PHASE=expand uv run pytest -rA -s -q compat/test_v1.py > "$OUT/expand.log" 2>&1)
  say "EXPAND exit=$? $(tail -1 "$OUT/expand.log")"
  (cd "$D" && brickkit upgrade "test/probe-go@$NEXT" --yes && brickkit build && brickkit up) > "$OUT/upgrade.log" 2>&1
  rc=$?; say "UPGRADE exit=$rc"
  if [ $rc != 0 ]; then
    # brickkit up runs every version's migration again; the older version's fails on the schema the default version
    # migrated (G4) and up stops before the new version migrates. The contract migration and the new version are
    # started by hand, as another node's deploy would have, while the older version keeps running.
    p=brickkit-d12-v1-test-probe-go-${NEXT//./-}
    docker start -a "$p-migration-1" > "$OUT/contract-migration.log" 2>&1; say "CONTRACT-MIGRATION exit=$?"
    docker start "$p-1" > /dev/null 2>&1
    for _ in $(seq 60); do docker ps --filter "name=$p-1" --format '{{.Status}}' | grep -q healthy && break; sleep 1; done
    say "NEW $(docker ps --filter "name=$p-1" --format '{{.Status}}')"
  fi
  keep contract
  (cd "$CONF" && BE_ACC_CELL=$D V1_PHASE=contract uv run pytest -rA -s -q compat/test_v1.py > "$OUT/contract.log" 2>&1)
  say "CONTRACT exit=$? $(tail -1 "$OUT/contract.log")"
else
  say "FAILED bring-up"
fi
mkdir -p "$OUT/logs"
for n in $(docker ps -a --filter "label=com.docker.compose.project=brickkit-d12-v1" --format '{{.Names}}'); do
  docker logs "$n" > "$OUT/logs/$n.log" 2>&1; done
(cd "$D" && brickkit down) > "$OUT/down.log" 2>&1
say "ALL-DONE"
