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
# FROM=<stage> resumes a failed run at that stage.
# Usage: cell-chain.sh <cell name, e.g. D8-S> <output directory>
set -u
CELL=$1; OUT=$(realpath -m "$2"); R=/home/zhijie/Desktop/github/be-assembly-standard
D=$R/dev/rebuild/experiment-cells/$CELL; CONF=${CONF:-$R/tools/be-acceptance/conformance}
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl for the K row (bin/kubectl)
ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); ROW=${ROW:-D}
# step 10 B7: a cell with `base: cluster` has the base resources in the K row's cluster, on other host ports
# (cluster-create.sh, base-cluster/base-cluster.sh)
INCLUSTER=; grep -q '^base: *cluster' "$D/cell.yaml" && INCLUSTER=1
mkdir -p "$OUT/logs"; echo $$ > "$OUT/runner.pid"
. "$R/dev/rebuild/experiment-scripts/cellenv.sh" "$D"  # the passwords, BE_ACC_*, Casdoor's client secrets (PGP, NP, SP)
[ -n "${BE_OPS:-}" ] || build_be_ops "$(mktemp -d)"  # outside the output directory (no binaries in the repository); prepare issues a secured cell's certificates with be-ops (C1 E6: unset once)
I=0
stage() {  # stage <name> <command...>; stops the run on failure. FROM=<name> skips the stages before that one (a run
  # that failed there resumes on the cell as it is)
  I=$((I+1)); local name=$1; shift; local t0; t0=$(date +%s)
  if [ -n "${FROM:-}" ]; then
    if [ "$name" = "$FROM" ]; then FROM=; else echo "STAGE $I $name SKIPPED" >> "$OUT/status.log"; return 0; fi
  fi
  echo "STAGE $I $name BEGIN $(date -Is)" >> "$OUT/status.log"
  ( "$@" ) > "$OUT/logs/$I-$name.log" 2>&1; local rc=$?
  echo "STAGE $I $name END exit=$rc secs=$(( $(date +%s) - t0 ))" >> "$OUT/status.log"
  if [ $rc -ne 0 ]; then echo "FAILED $name $(date -Is)" >> "$OUT/status.log"; pod_logs; exit $rc; fi
}
pod_logs() {  # every row: the cell's logs kept beside the stage logs when a stage fails (cell-logs.sh); a runner that
  # takes the cell down afterwards would lose them (T9's first F3-S, D row, retro-foundations-03.md M1)
  bash "$R/dev/rebuild/experiment-scripts/cell-logs.sh" "$D" "$OUT/logs/containers" "$ROW"
}
down_cells() {  # every experiment cell on every engine (projects brickkit-<cell>, namespaces <cell> in minikube)
  # suite E's front doors first: a project network with a container still attached cannot be removed
  for eng in docker podman; do $eng ps -a --format '{{.Names}}' 2>/dev/null | grep '^front-' | xargs -r $eng rm -f >/dev/null; done
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
# rootless Podman only: a rootful cell (cell.yaml `podman: rootful`) needs no user namespace. With compose it is reached
# through root's socket (CONTAINER_HOST); with Quadlet units (`units: quadlet`, FRR-025) root itself runs `brickkit up`
# (rootful/quadlet-up.sh, which also loads the images), and the up stage waits for every component to answer
ROOTQ=; grep -q '^podman: *rootful' "$D/cell.yaml" && grep -q '^units: *quadlet' "$D/cell.yaml" && ROOTQ=1
if grep -q '^podman: *rootful' "$D/cell.yaml"; then [ -n "$ROOTQ" ] || export CONTAINER_HOST=unix:///run/podman/podman.sock
else case $ROW in P|LP) stage podman-preflight bash "$R/dev/rebuild/experiment-scripts/podman-preflight.sh" ;; esac; fi
stage down-others down_cells
# suite E5: a cell with a schema on the second instance (databases: ... second/<database>) starts it afresh first
grep -qE '^  [^ ]+: *second/' "$D/cell.yaml" && stage postgres2 bash "$R/dev/rebuild/experiment-scripts/postgres2.sh" up
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
# C7 retro R3: the public Go proxy serves every module the Go shells pin (a cached failed fetch otherwise shows up only
# as "git not found" inside the build); waits up to PROXY_WAIT minutes
[ "$ROW" = L ] || stage proxy bash "$R/dev/rebuild/experiment-scripts/proxy-check.sh" "$D"
[ "$ROW" = L ] || stage build build  # the L row runs from source: no images
# after the build: a shell's new version exists only then
[ -n "$ROOTQ" ] || case $ROW in P|LP|K) stage images images ;; esac
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
elif [ -n "$ROOTQ" ]; then
  # root's `brickkit up` evaluates the ${VAR}s itself: the cell's .env (gitignored) hands it the two this runner exports
  (umask 077; printf 'BE_ACC_IAM_CLIENT_SECRET=%s\nBE_ACC_IAM_DEV_CLIENT_SECRET=%s\n' "$BE_ACC_IAM_CLIENT_SECRET" \
    "$BE_ACC_IAM_DEV_CLIENT_SECRET" > "$D/.env")
  echo "WAITING for: sudo dev/rebuild/experiment-scripts/rootful/quadlet-up.sh $CELL $(date -Is)" >> "$OUT/status.log"
  stage up-by-root bash -c "cd $CONF && uv run python -c 'import sys, yaml; from cells.units import wait_answering; wait_answering([c[\"exposePort\"] for c in yaml.safe_load(open(sys.argv[1]))[\"components\"] if \"exposePort\" in c], timeout=3600)' $D/deploy.yaml"
else
  stage up bash -c "cd $D && brickkit up"
  # suite E: a replicated shell or component maps no host port on Docker and Podman; a front door takes it
  grep -q '^replicas:' "$D/cell.yaml" && [ "$ROW" != K ] && stage front bash -c "cd $CONF && uv run python -m cells front up $D"
fi
# then wait until every one answers: a Service just made is not routed at once (step 12, K12-V4's first call was reset)
[ "$ROW" = K ] && stage nodeports bash -c "cd $CONF && uv run python -c 'import sys; from cells.spec import Cell; from cells.units import nodeports, host_ports_of, wait_answering; made = nodeports(Cell.load(sys.argv[1])); print(made); wait_answering(host_ports_of(made))' $D"
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
[ "${KEEP_UP:-1}" = 0 ] && { stage down bash -c "cd $CONF && uv run python -m cells front down $D; cd $D && brickkit down && cd $CONF && uv run python -m cells.localrun down $D"
  stop_forward "$(forward_pid "$D")"; docker rm -f be-pgbouncer >/dev/null 2>&1; docker rm -fv be-postgres-2 >/dev/null 2>&1; }
echo "ALL-DONE $(date -Is)" >> "$OUT/status.log"
