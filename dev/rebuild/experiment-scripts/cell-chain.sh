#!/bin/bash
# Step 8: brings one business-chain cell up from nothing and checks it: create, prepare, build, up, secure, seed data
# (twice: the second run must change nothing), the L3 scenarios. Stages write BEGIN/END lines to <out>/status.log, each
# stage's output to its own log; the first failing stage stops the run. The cell stays up unless KEEP_UP=0. SEED=0 stops
# after secure: a deployment as installed, with its install claim but no seed data (and so no L3).
# The cell's row (cell.yaml) picks the engine: P loads the Docker-built images into Podman first (the same images in
# every row), K into the minikube node (cells/kube.py also adds the NodePort Services). CONF may point at a snapshot of
# the conformance tools, so that editing them does not change a run in progress. A seed run that fails is retried
# once after 70 s (the authorization view after the shell restart: 8-01 section 6), and the retry is recorded.
# Usage: cell-chain.sh <cell name, e.g. D8-S> <output directory>
set -u
CELL=$1; OUT=$(realpath -m "$2"); R=/home/zhijie/Desktop/github/be-assembly-standard
D=$R/dev/rebuild/experiment-cells/$CELL; CONF=${CONF:-$R/tools/be-acceptance/conformance}
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl for the K row (bin/kubectl)
ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); ROW=${ROW:-D}
mkdir -p "$OUT/logs"; echo $$ > "$OUT/runner.pid"
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export SEED_PASSWORD; SEED_PASSWORD=$(envval IAM_TEST_PASSWORD)
export IAM_TEST_PASSWORD="$SEED_PASSWORD" BE_ACC_IAM_TEST_PASSWORD="$SEED_PASSWORD" BE_ACC_CELL="$D"
export CASDOOR_ADMIN_PASSWORD; CASDOOR_ADMIN_PASSWORD=$(envval CASDOOR_ADMIN_PASSWORD)
export BE_ACC_PG_ADMIN; BE_ACC_PG_ADMIN="postgres://postgres:$(envval POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
export BE_ACC_NATS_URL=nats://localhost:4222 BE_ACC_S3_URL=http://localhost:9000
export BE_ACC_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY; BE_ACC_S3_ACCESS_KEY=$(envval STORAGE_ACCESS_KEY); BE_ACC_S3_SECRET_KEY=$(envval STORAGE_SECRET_KEY)
# the identity member's Casdoor applications: their client secrets live in Casdoor's own tables (local dev Casdoor)
casdoor_secret() { docker exec -e PGPASSWORD="$(envval POSTGRES_PASSWORD)" be-postgres psql -U postgres -d brickkit_db -Atc \
  "select client_secret from casdoor.application where client_id = '$1'"; }
export BE_ACC_IAM_CLIENT_SECRET BE_ACC_IAM_DEV_CLIENT_SECRET
BE_ACC_IAM_CLIENT_SECRET=$(casdoor_secret be-iam-client); BE_ACC_IAM_DEV_CLIENT_SECRET=$(casdoor_secret be-iam-dev-client)
I=0
stage() {  # stage <name> <command...>; stops the run on failure
  I=$((I+1)); local name=$1; shift; local t0; t0=$(date +%s)
  echo "STAGE $I $name BEGIN $(date -Is)" >> "$OUT/status.log"
  ( "$@" ) > "$OUT/logs/$I-$name.log" 2>&1; local rc=$?
  echo "STAGE $I $name END exit=$rc secs=$(( $(date +%s) - t0 ))" >> "$OUT/status.log"
  if [ $rc -ne 0 ]; then echo "FAILED $name $(date -Is)" >> "$OUT/status.log"; exit $rc; fi
}
down_cells() {  # every experiment cell on every engine (projects brickkit-<cell>, namespaces <cell> in minikube)
  for p in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep -E '^brickkit-[dplk][0-9]' | sort -u); do
    docker compose -p "$p" down --remove-orphans; done
  for p in $(podman ps -a --format '{{index .Labels "com.docker.compose.project"}}' 2>/dev/null | grep -E '^brickkit-[dplk][0-9]' | sort -u); do
    podman compose -p "$p" down --remove-orphans; done
  if minikube -p bek status >/dev/null 2>&1; then
    for n in $(minikube -p bek kubectl -- get ns -o name 2>/dev/null | sed 's|namespace/||' | grep -E '^[dplk][0-9]-'); do
      minikube -p bek kubectl -- delete ns "$n" --wait=true; done
  fi
  pkill -INT -f "brickkit up" 2>/dev/null; pkill -f "cells.localrun forward" 2>/dev/null; true  # the L row's sessions
}
images() {  # the Docker-built images of every component in the cell into the row's engine (same images in every row)
  local img
  for img in $(python3 -c 'import sys,yaml; [print(c["id"].replace("/","-")+":"+c["version"]) for c in yaml.safe_load(open(sys.argv[1]))["components"]]' "$D/brickkit.yaml"); do
    case $ROW in
      P) docker save "$img" | podman load -q || return 1 ;;
      K) minikube -p bek image load "$img" || return 1 ;;
    esac
  done
}
echo "START $CELL power=$(powerprofilesctl get) $(date -Is)" >> "$OUT/status.log"
stage down-others down_cells
stage create bash -c "cd $CONF && uv run python -m cells create $D && uv run python -m cells prepare $D"
[ "$ROW" = P ] || [ "$ROW" = K ] && stage images images
[ "$ROW" = L ] || stage build bash -c "cd $D && brickkit build"  # the L row runs from source: no images
if [ "$ROW" = K ]; then
  # K row: the authorization member submits its own definitions through its own Service, which only routes to ready
  # pods, and it is ready only after that submission: it never becomes ready (step 9 finding). The cell lets the
  # Service route to the pod before it is ready (publishNotReadyAddresses) while `brickkit up` waits; recorded in 9-01.
  authz_svc() { kubectl --context bek -n "$(echo "$CELL" | tr 'A-Z' 'a-z')" get svc -o name | grep '/infra-authz-'; }
  up_k() {
    (cd "$D" && brickkit up) & local pid=$! s=""
    for _ in $(seq 120); do s=$(authz_svc) && [ -n "$s" ] && break; sleep 2; done
    [ -n "$s" ] && kubectl --context bek -n "$(echo "$CELL" | tr 'A-Z' 'a-z')" patch "$s" -p '{"spec":{"publishNotReadyAddresses":true}}'
    wait $pid
  }
  stage up up_k
elif [ "$ROW" = L ]; then
  # L row: a mode: local session in the background (cells/localrun.py), and host port 10000 + port forwarded to each
  # process's own port, as Docker's proxy does for a container
  stage up bash -c "cd $CONF && uv run python -m cells.localrun up $D $OUT/logs/local-session.log"
  (cd "$CONF" && setsid nohup uv run python -m cells.localrun forward "$D" > "$OUT/logs/forward.log" 2>&1 &)
else
  stage up bash -c "cd $D && brickkit up"
fi
[ "$ROW" = K ] && stage nodeports bash -c "cd $CONF && uv run python -c 'import sys; from cells.spec import Cell; from cells.units import nodeports; print(nodeports(Cell.load(sys.argv[1])))' $D"
stage secure bash -c "cd $CONF && uv run python -m cells secure $D"
if [ "${SEED:-1}" != 0 ]; then
  stage seed-1 bash -c "make -C $R seed-data || { echo 'RETRY seed after 70 s'; sleep 70; make -C $R seed-data; }"
  stage seed-2 make -C "$R" seed-data
  stage scenarios bash -c "cd $CONF && uv run pytest -q scenarios"
fi
[ "${KEEP_UP:-1}" = 0 ] && stage down bash -c "cd $D && brickkit down"
echo "ALL-DONE $(date -Is)" >> "$OUT/status.log"
