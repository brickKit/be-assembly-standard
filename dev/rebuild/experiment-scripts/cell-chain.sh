#!/bin/bash
# Step 8: brings one business-chain cell up from nothing and checks it: create, prepare, build, up, secure, seed data
# (twice: the second run must change nothing), the L3 scenarios. Stages write BEGIN/END lines to <out>/status.log, each
# stage's output to its own log; the first failing stage stops the run. The cell stays up unless KEEP_UP=0. SEED=0 stops
# after secure: a deployment as installed, with its install claim but no seed data (and so no L3).
# The cell's row (cell.yaml) picks the engine: P loads the Docker-built images into Podman first (the same images in
# every row), K into the minikube node (cells/kube.py also adds the NodePort Services). CONF may point at a snapshot of
# the conformance tools, so that editing them does not change a run in progress. MOVE=1 (D and P rows) adds the
# regression of 8-01 section 6 after the seeds: the authorization member restarts on another IP address and the L3
# scenarios, which never retry, run as soon as it is ready again.
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
  if [ $rc -ne 0 ]; then echo "FAILED $name $(date -Is)" >> "$OUT/status.log"; pod_logs; exit $rc; fi
}
pod_logs() {  # K row: every pod's log of the cell, kept beside the stage logs when a stage fails
  [ "$ROW" = K ] || return 0
  local ns p; ns=$(echo "$CELL" | tr 'A-Z' 'a-z'); mkdir -p "$OUT/logs/pods"
  for p in $(kubectl --context bek -n "$ns" get pods -o name 2>/dev/null); do
    kubectl --context bek -n "$ns" logs "$p" --all-containers > "$OUT/logs/pods/${p#pod/}.log" 2>&1; done
}
down_cells() {  # every experiment cell on every engine (projects brickkit-<cell>, namespaces <cell> in minikube)
  for p in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep -E '^brickkit-[dplk]{1,2}[0-9]' | sort -u); do
    docker compose -p "$p" down --remove-orphans; done
  for p in $(podman ps -a --format '{{index .Labels "com.docker.compose.project"}}' 2>/dev/null | grep -E '^brickkit-[dplk]{1,2}[0-9]' | sort -u); do
    podman compose -p "$p" down --remove-orphans; done
  if minikube -p bek status >/dev/null 2>&1; then
    for n in $(minikube -p bek kubectl -- get ns -o name 2>/dev/null | sed 's|namespace/||' | grep -E '^[dplk]{1,2}[0-9]-'); do
      minikube -p bek kubectl -- delete ns "$n" --wait=true; done
  fi
  (cd "$CONF" && uv run python -m cells.localrun down "$D") 2>/dev/null  # the L, LD, LP rows' sessions, by PID
  for f in "${XDG_RUNTIME_DIR:-/tmp}"/be-cell-forward-*.pid; do stop_forward "$f"; done
  docker rm -f be-pgbouncer >/dev/null 2>&1; true  # a pooler cell's PgBouncer
}
# a cell with `pooler: pgbouncer` (step 10, B1): PgBouncer on the base resources' network, host port 6432, with the
# configuration cells prepare wrote (transaction mode); the components' running connections go through it
PGBOUNCER=edoburu/pgbouncer@sha256:9c78945868a6a142c7fc40ccd843bbe5a606df163c7ffce4de70e0d628d696a2  # PgBouncer 1.26.0
pooler() {
  docker run -d --name be-pgbouncer --network be-net -p 6432:6432 -v "$D/.secrets/pgbouncer:/etc/pgbouncer:ro" "$PGBOUNCER" \
    || return 1
  local t0; t0=$(date +%s)
  until bash -c '</dev/tcp/127.0.0.1/6432' 2>/dev/null; do
    [ $(( $(date +%s) - t0 )) -gt 30 ] && { docker logs be-pgbouncer; return 1; }; sleep 1; done
  docker exec be-pgbouncer pgbouncer --version
}
# the L row's port forwarder: its process group leader's PID, outside the cell (brickkit down clears .brickkit/)
forward_pid() { echo "${XDG_RUNTIME_DIR:-/tmp}/be-cell-forward-$(basename "$1").pid"; }
stop_forward() {  # stop_forward <pid file>: the L row's port forwarder, by its process group (setsid made it the leader)
  [ -f "$1" ] || return 0
  kill -- -"$(cat "$1")" 2>/dev/null; rm -f "$1"
}
images() {  # the Docker-built images of every component in the cell into the row's engine (same images in every row);
  # what runs on this machine (cell.yaml local:) has no image
  local img
  for img in $(python3 -c 'import sys,yaml
local = {x.split("@")[0] for x in yaml.safe_load(open(sys.argv[2])).get("local") or []}
[print(c["id"].replace("/","-")+":"+c["version"]) for c in yaml.safe_load(open(sys.argv[1]))["components"] if c["id"] not in local]' "$D/brickkit.yaml" "$D/cell.yaml"); do
    case $ROW in
      # Podman resolves the short name to localhost/ first: the Docker-built image takes that name too
      P|LP) docker save "$img" | podman load -q && podman tag "docker.io/library/$img" "localhost/$img" || return 1 ;;
      K) minikube -p bek image load "$img" || return 1 ;;
    esac
  done
}
echo "START $CELL power=$(powerprofilesctl get) $(date -Is)" >> "$OUT/status.log"
stage down-others down_cells
stage create bash -c "cd $CONF && uv run python -m cells create $D && uv run python -m cells prepare $D"
grep -q '^pooler: *pgbouncer' "$D/cell.yaml" && stage pooler pooler
build() {  # every row's images come from Docker (the same images in every row): P and LP build as a docker target
  if [ "$ROW" = P ] || [ "$ROW" = LP ]; then
    cp "$D/deploy.yaml" "$D/.deploy.yaml.p" && sed -i 's/^target: podman$/target: docker/' "$D/deploy.yaml"
    (cd "$D" && brickkit build); local rc=$?
    mv "$D/.deploy.yaml.p" "$D/deploy.yaml"; return $rc
  fi
  (cd "$D" && brickkit build)
}
[ "$ROW" = L ] || stage build build  # the L row runs from source: no images
case $ROW in P|LP|K) stage images images ;; esac  # after the build: a shell's new version exists only then
move_authz() {  # the container serving infra/authz (alone or in be/go-infra) restarts on another address of its network
  local eng=docker c net old new aliases a args=()
  [ "$ROW" = P ] && eng=podman
  c=$($eng ps --format '{{.Names}}' | grep -iE "^brickkit-$CELL[-_].*(infra-authz|be-go-infra)" | head -1)
  [ -n "$c" ] || { echo "no authorization container in $CELL"; return 1; }
  net=$($eng inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$c" | head -1)
  old=$($eng inspect -f "{{(index .NetworkSettings.Networks \"$net\").IPAddress}}" "$c")
  aliases=$($eng inspect -f "{{range (index .NetworkSettings.Networks \"$net\").Aliases}}{{.}} {{end}}" "$c")
  new=${old%.*}.$(( (${old##*.} + 100) % 250 + 2 ))
  for a in $aliases; do args+=(--alias "$a"); done
  echo "moving $c on $net from $old to $new (aliases: $aliases)"
  $eng stop "$c" && $eng network disconnect "$net" "$c" && $eng network connect --ip "$new" "${args[@]}" "$net" "$c" \
    && $eng start "$c" || return 1
  local t0; t0=$(date +%s)
  until [ "$($eng inspect -f '{{.State.Health.Status}}' "$c")" = healthy ]; do
    [ $(( $(date +%s) - t0 )) -gt 120 ] && { echo "not healthy after 120 s"; return 1; }; sleep 1; done
  echo "healthy again after $(( $(date +%s) - t0 )) s at $($eng inspect -f "{{(index .NetworkSettings.Networks \"$net\").IPAddress}}" "$c")"
}
if [ "$ROW" = L ] || [ "$ROW" = LD ] || [ "$ROW" = LP ]; then
  # L, LD, LP rows: a mode: local session in the background (cells/localrun.py; it starts the containers too), and
  # host port 10000 + port forwarded to each process's own port, as Docker's proxy does for a container
  stage up bash -c "cd $CONF && uv run python -m cells.localrun up $D $OUT/logs/local-session.log"
  # the shell after setsid writes its own PID (the group leader; setsid may fork first) and becomes the forwarder
  (cd "$CONF" && setsid bash -c 'echo $$ > "$1"; exec uv run python -m cells.localrun forward "$2"' _ \
    "$(forward_pid "$D")" "$D" < /dev/null > "$OUT/logs/forward.log" 2>&1 &)
else
  stage up bash -c "cd $D && brickkit up"
fi
[ "$ROW" = K ] && stage nodeports bash -c "cd $CONF && uv run python -c 'import sys; from cells.spec import Cell; from cells.units import nodeports; print(nodeports(Cell.load(sys.argv[1])))' $D"
# the install claim only where the security members run (a probe cell has none)
grep -q 'infra/iam-casdoor' "$D/cell.yaml" && stage secure bash -c "cd $CONF && uv run python -m cells secure $D"
if [ "${SEED:-1}" != 0 ]; then
  stage seed-1 make -C "$R" seed-data
  stage seed-2 make -C "$R" seed-data
  stage scenarios bash -c "cd $CONF && uv run pytest -q scenarios"
  if [ "${MOVE:-0}" = 1 ] && { [ "$ROW" = D ] || [ "$ROW" = P ]; }; then
    stage move-authz move_authz
    stage scenarios-after-move bash -c "cd $CONF && uv run pytest -q scenarios"
  fi
fi
# brickkit down does not reach a mode: local session's processes: cells/localrun.py stops the session by its PID
[ "${KEEP_UP:-1}" = 0 ] && { stage down bash -c "cd $D && brickkit down && cd $CONF && uv run python -m cells.localrun down $D"
  stop_forward "$(forward_pid "$D")"; docker rm -f be-pgbouncer >/dev/null 2>&1; }
echo "ALL-DONE $(date -Is)" >> "$OUT/status.log"
