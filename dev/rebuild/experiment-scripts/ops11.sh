#!/bin/bash
# Step 11 (step11-plan.md), suite C's operations on a running cell under the background load (runner11.sh calls them;
# each can also run alone). Every action prints timed lines; what changed is in <out>.
#   burst <cell> <out>    R3: a burst of billing and printing (load -flow print, BURST_RATE/s for BURST_SECONDS)
#                         beside the background mix: what it does to the mix is in the mix's per-second series
#   upgrade <cell> <out>  R4: UPGRADE_REFS (id@version ..., in order) are a patch release newer than the cell's: a
#                         component with the dependents that name its version, from the bottom up, or the be/go-core
#                         that hosts them. Step 11 ran erp/inventory@3.0.9 erp/sales@3.0.14 erp/billing@3.0.13, and
#                         be/go-core@3.0.38 for a cell with the shell. brickkit upgrade, build, the images into the
#                         row's engine, up; which containers or pods were replaced, and when
#   split <cell> <out>    R5: be/go-core's members out of the shell to run alone (deploy.yaml: their entries to the top
#                         level), up, the L3 scenarios; then back into the shell, up, the L3 scenarios. A cell without
#                         be/go-core (X) does it the other way round: into a be/go-core first, then out again
#   conns <cell>          the connections by database role, database and application name (ST07: each process's
#                         pools reach only their own targets)
# Usage: ops11.sh <action> <cell> [<out>]
set -u
ACT=$1; CELL=$2; OUT=${3:-}; R=/home/zhijie/Desktop/github/be-assembly-standard
D=$R/dev/rebuild/experiment-cells/$CELL; CONF=${CONF:-$R/tools/be-acceptance/conformance}
ROW=$(sed -n 's/^row: *//p' "$D/cell.yaml"); ROW=${ROW:-D}
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export BE_ACC_IAM_TEST_PASSWORD; BE_ACC_IAM_TEST_PASSWORD=$(envval IAM_TEST_PASSWORD)
export BE_ACC_PG_ADMIN; BE_ACC_PG_ADMIN="postgres://postgres:$(envval POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
# brickkit up resolves the identity member's Casdoor client secrets from the environment (as cell-chain.sh)
casdoor_secret() { docker exec -e PGPASSWORD="$(envval POSTGRES_PASSWORD)" be-postgres psql -U postgres -d brickkit_db -Atc \
  "select client_secret from casdoor.application where client_id = '$1'"; }
export BE_ACC_IAM_CLIENT_SECRET BE_ACC_IAM_DEV_CLIENT_SECRET
BE_ACC_IAM_CLIENT_SECRET=$(casdoor_secret be-iam-client); BE_ACC_IAM_DEV_CLIENT_SECRET=$(casdoor_secret be-iam-dev-client)
say() { echo "$(date -Is) $*"; }
[ -n "$OUT" ] && mkdir -p "$OUT"
eng() { case $ROW in P|LP) echo podman ;; *) echo docker ;; esac; }
units() {  # the cell's containers (or pods) with when each started
  if [ "$ROW" = K ]; then kubectl --context bek -n "${CELL,,}" get pods -o \
    jsonpath='{range .items[*]}{.metadata.name} {.status.startTime}{"\n"}{end}'
  else $(eng) ps --filter "label=com.docker.compose.project=brickkit-${CELL,,}" --format '{{.Names}} {{.CreatedAt}}' | sort; fi
}
build() {  # as cell-chain.sh: every row's images come from Docker, then into Podman or the minikube node
  if [ "$ROW" = P ]; then
    cp "$D/deploy.yaml" "$D/.deploy.yaml.p" && sed -i 's/^target: podman$/target: docker/' "$D/deploy.yaml"
    (cd "$D" && brickkit build); local rc=$?; mv "$D/.deploy.yaml.p" "$D/deploy.yaml"; [ $rc = 0 ] || return $rc
  else (cd "$D" && brickkit build) || return 1; fi
  local img
  for img in $(python3 -c 'import sys,yaml
[print(c["id"].replace("/","-")+":"+c["version"]) for c in yaml.safe_load(open(sys.argv[1]))["components"]]' "$D/brickkit.yaml"); do
    case $ROW in
      P) docker save "$img" | podman load -q && podman tag "docker.io/library/$img" "localhost/$img" || return 1 ;;
      K) minikube -p bek image load "$img" || return 1 ;;
    esac
  done
}
up() {  # on Kubernetes the driver reaches each component through a NodePort Service the cell tools add (cells/kube.py,
  # as cell-chain.sh does after its up): they select pods by name, so they are made again for the new topology
  (cd "$D" && brickkit up) || return 1
  [ "$ROW" = K ] || return 0
  (cd "$CONF" && uv run python -c 'import sys; from cells.spec import Cell; from cells.units import nodeports; print(nodeports(Cell.load(sys.argv[1])))' "$D")
}
healthy() {  # every container or pod of the cell healthy again (at most 300 s)
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    if [ "$ROW" = K ]; then
      [ -z "$(kubectl --context bek -n "${CELL,,}" get deploy -o jsonpath='{range .items[*]}{.status.unavailableReplicas}{end}')" ] && return 0
    else
      [ -z "$($(eng) ps --filter "label=com.docker.compose.project=brickkit-${CELL,,}" --format '{{.Status}}' | grep -v '(healthy)')" ] && return 0
    fi
    sleep 1
  done
  return 1
}
ready() {  # every component of the cell answers /readyz with 200 (at most 120 s). Docker's health check asks /healthz,
  # which answers once the port listens; the module is ready only after its start (up to 2 s more), and until then
  # answers 503 NOT_READY, which a caller's circuit breaker counts. A pod takes traffic only once ready (healthy waits)
  [ "$ROW" = K ] && return 0
  (cd "$CONF" && uv run python -c 'import asyncio, sys
from cells.spec import Cell
from cells.secure import ready
c = Cell.load(sys.argv[1])
async def main():
    await asyncio.gather(*(ready(f"http://127.0.0.1:{c.host_port(x)}") for x in c.placed))
asyncio.run(main())' "$D")
}
scenarios() { (cd "$CONF" && BE_ACC_CELL=$D uv run pytest -q scenarios); }
timed() {  # timed <name> <command...>: one line with the seconds it took and its status
  local name=$1 t0 rc; shift; t0=$(date +%s.%N); "$@"; rc=$?
  say "STEP $name exit=$rc secs=$(printf '%.1f' "$(echo "$(date +%s.%N) - $t0" | bc)")"; return $rc
}
case $ACT in
  burst)
    (cd "$CONF" && uv run python -m cells world "$D" "$OUT/burst-world.json") || exit 1
    [ -x "$OUT/load" ] || (cd "$CONF/../load" && go build -o "$OUT/load" .) || exit 1
    say "BURST rate=${BURST_RATE:-10} seconds=${BURST_SECONDS:-30}"
    BE_LOAD_PASSWORD=$BE_ACC_IAM_TEST_PASSWORD "$OUT/load" -flow print -world "$OUT/burst-world.json" \
      -credentials "$D/.secrets/load-user.json" -rate "${BURST_RATE:-10}" -warmup 0s -duration "${BURST_SECONDS:-30}s" \
      -out "$OUT/burst.json" -series "$OUT/burst-series.json"; say "BURST exit=$?"
    ;;
  upgrade)
    units > "$OUT/units-before.txt"
    # the release to upgrade to names versions newer than the cell's, so it is given each time, not kept here
    REFS=${UPGRADE_REFS:-}; [ -n "$REFS" ] || { say "UPGRADE needs UPGRADE_REFS (id@version ...)"; exit 64; }
    say "UPGRADE $REFS"
    for REF in $REFS; do timed "upgrade-$REF" bash -c "cd $D && brickkit upgrade $REF --yes" || exit 1; done
    timed build build || exit 1
    timed up up || exit 1
    timed healthy healthy || exit 1
    timed ready ready || exit 1
    units > "$OUT/units-after.txt"
    say "REPLACED $(diff "$OUT/units-before.txt" "$OUT/units-after.txt" | sed -n 's/^> //p' | awk '{print $1}' | tr '\n' ' ')"
    ;;
  split)
    cp "$D/deploy.yaml" "$OUT/deploy-before.yaml"; cp "$D/brickkit.yaml" "$OUT/brickkit-before.yaml"
    # the shell that compiles the members' current versions in: the cell's own (H), else the current release (X);
    # after an R4 upgrade in the same run that is the upgraded shell, which R4 writes into neither: run split before it
    SHELL_REF=$(grep -oE 'be/go-core@[0-9.]+' "$D/cell.yaml" | head -1)
    [ -n "$SHELL_REF" ] || SHELL_REF=be/go-core@$(sed -n 's/^ *version: *//p' "$R/shell/be/go-core/component.yaml" | head -1)
    move() {  # move out: be/go-core's four trading members to the top level of deploy.yaml
      python3 - "$D/deploy.yaml" "$1" <<'EOF2'
import sys, yaml
path, way = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(path))
trading = ["erp/inventory", "erp/credit", "erp/sales", "erp/billing"]
comps = d["components"]
shell = next((c for c in comps if c["id"] == "be/go-core"), None)
if way == "out":
    comps.extend(shell.pop("members"))  # the shell's entry stays, empty, for brickkit remove to take away
else:
    if shell is None:
        shell = {"id": "be/go-core"}
        comps.append(shell)
    shell["members"] = [c for c in comps if c["id"] in trading]
    for m in shell["members"]:
        comps.remove(m)
open(path, "w").write(yaml.safe_dump(d, sort_keys=False))
EOF2
    }
    # out: the members to the top level, then the shell leaves the project (brickkit remove); in: the shell joins the
    # project (brickkit add), then the members go under it. Each way: build, up, the L3 scenarios
    out_way() { move out && (cd "$D" && brickkit remove be/go-core < /dev/null); }
    # brickkit add moves the members already in the project under the shell by itself, and adds the other members the
    # shell compiles in (the Go probes): those leave again (hosting only some members)
    in_way() {
      (cd "$D" && brickkit add "$SHELL_REF" --yes) || return 1
      local extra
      for extra in $(python3 -c 'import sys,yaml
before = {c["id"] for c in yaml.safe_load(open(sys.argv[1]))["components"]} | {"be/go-core"}
print(" ".join(sorted({c["id"] for c in yaml.safe_load(open(sys.argv[2]))["components"]} - before)))' "$OUT/brickkit-before.yaml" "$D/brickkit.yaml"); do
        (cd "$D" && brickkit remove "$extra" < /dev/null) || return 1
      done
      # the shell's own login role, holding the members' runtime roles, and its config: a shell new to the project
      # (the X cell) has neither, and would refuse to start (exit 78)
      (cd "$CONF" && uv run python -m cells join-shell "$D" be/go-core erp/inventory erp/credit erp/sales erp/billing)
    }
    if grep -q 'be/go-core' "$D/cell.yaml"; then WAYS="out in"; else WAYS="in out"; fi
    BAD=0  # the scenarios failing either way fails the action (the next way still runs)
    for WAY in $WAYS; do
      say "SPLIT $WAY ($SHELL_REF)"; timed "move-$WAY" "${WAY}_way" || exit 1
      units > "$OUT/units-before-$WAY.txt"
      timed "build-$WAY" build || exit 1
      timed "up-$WAY" up || exit 1
      timed "healthy-$WAY" healthy || exit 1
      timed "ready-$WAY" ready || exit 1
      units > "$OUT/units-after-$WAY.txt"
      "$0" conns "$CELL" > "$OUT/conns-$WAY.txt"
      timed "scenarios-$WAY" scenarios || { say "SPLIT $WAY scenarios FAILED"; BAD=1; }
    done
    exit $BAD
    ;;
  conns)
    # by role, database and application name: the base resources are reached through the host's gateway, so the client
    # address is the same for every process; a shell logs in as its own role (shell_*) and switches per transaction
    docker exec -e PGPASSWORD="$(envval POSTGRES_PASSWORD)" be-postgres psql -U postgres -d postgres -AtF ' ' -c \
      "SELECT usename, datname, coalesce(nullif(application_name, ''), '-'), count(*) FROM pg_stat_activity
       WHERE usename <> 'postgres' AND backend_type = 'client backend' GROUP BY 1, 2, 3 ORDER BY 1, 2, 3"
    ;;
  *) echo "unknown action $ACT" >&2; exit 64 ;;
esac
