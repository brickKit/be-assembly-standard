#!/bin/bash
# Runs one night script the way step 10's nights ran: the conformance tools from a snapshot (CONF, a copy of the WHOLE
# be-acceptance checkout: the load driver's source lives in load/, outside conformance/), the power mode switched to
# performance and restored on exit or stop, and the containers, Podman and `brickkit up` sessions still running
# afterwards listed as leftovers. <wrapdir> gets wrap.pid (the process to watch) and wrap.log (ends with WRAP ALL-DONE).
# Start it under systemd-inhibit, in the background:
#   rsync -a --exclude .git --exclude .venv --exclude __pycache__ tools/be-acceptance/ <snap>/ && (cd <snap>/conformance && uv sync -q)
#   CONF=<snap>/conformance systemd-inhibit --what=sleep:idle:handle-lid-switch --who=be-measure --why=<night> \
#     dev/rebuild/experiment-scripts/night-wrap.sh <wrapdir> dev/rebuild/experiment-scripts/<night>.sh <out>
# Usage: night-wrap.sh <wrapdir> <night script> <out>
set -u
W=$1; N=$2; OUT=$3; : "${CONF:?CONF must point at a snapshot of be-acceptance/conformance}"
mkdir -p "$W"; echo $$ > "$W/wrap.pid"; export CONF
P0=$(powerprofilesctl get 2>/dev/null); powerprofilesctl set performance
trap 'exit 143' TERM INT
trap 'powerprofilesctl set "$P0"; echo "WRAP power restored to $P0 $(date -Is)" >> "$W/wrap.log"' EXIT
echo "WRAP START $N out=$OUT power0=$P0 conf=$CONF $(date -Is)" >> "$W/wrap.log"
"$N" "$OUT"; echo "WRAP night exit=$? $(date -Is)" >> "$W/wrap.log"
docker ps --format '{{.Names}}' | grep -vE '^be-(postgres|casdoor|traefik|nats|rustfs)$' | sed 's/^/WRAP leftover docker /' >> "$W/wrap.log"
podman ps --format '{{.Names}}' 2>/dev/null | sed 's/^/WRAP leftover podman /' >> "$W/wrap.log"
pgrep -af 'brickkit up' | grep -v pgrep | sed 's/^/WRAP leftover proc /' >> "$W/wrap.log"
echo "WRAP ALL-DONE $(date -Is)" >> "$W/wrap.log"
