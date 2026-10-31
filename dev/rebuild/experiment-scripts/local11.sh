#!/bin/bash
# Step 11 (step11-plan.md section 1): the one suite C check on a row with processes on this machine. LD9-S runs sales
# and inventory as processes under one `brickkit up` session (mode: local), the rest in Docker. Sales crashes
# (SIGABRT, as in suite C): the other process should stop too, the session end listing the crash, the containers go
# on. Every half second for 60 s: whether each process and the session still run, how many of the cell's containers
# run. Then the cell goes down. Usage: local11.sh <out>   (CONF: a snapshot of the conformance tools)
set -u
OUT=$(realpath -m "$1"); R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
D=$R/dev/rebuild/experiment-cells/LD9-S; CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
log() { echo "$* $(date -Is)" >> "$OUT/status.log"; }
pid_on() { ss -ltnpH "sport = :$1" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null && echo 1 || echo 0; }
sessions() { (cd "$CONF" && uv run python -c 'from cells.localrun import sessions; print(" ".join(map(str, sessions())))'); }
containers() { docker ps --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}}' | wc -l; }
teardown() {
  (cd "$D" && brickkit down) >> "$OUT/down.log" 2>&1
  (cd "$CONF" && uv run python -m cells.localrun down "$D") >> "$OUT/down.log" 2>&1
  f="${XDG_RUNTIME_DIR:-/tmp}/be-cell-forward-LD9-S.pid"
  [ -f "$f" ] && { kill -- -"$(cat "$f")" 2>/dev/null; rm -f "$f"; }
}
log "START power=$(powerprofilesctl get)"
if ! KEEP_UP=1 "$X/cell-chain.sh" LD9-S "$OUT/bring-up" > "$OUT/bring-up.log" 2>&1; then
  log "FAILED bring-up"; teardown; log "ALL-DONE"; exit 1; fi
PROJECT=$(docker ps --format '{{.Label "com.docker.compose.project"}}' | grep -ix 'brickkit-ld9-s' | head -1)
S=$(pid_on 8084); I=$(pid_on 8086); SESS=$(sessions)
log "BEFORE sales=$S inventory=$I sessions=$SESS project=$PROJECT containers=$(containers)"
[ -n "$S" ] && [ -n "$I" ] && [ -n "$SESS" ] && [ -n "$PROJECT" ] || { log "FAILED no processes to watch"; teardown; log "ALL-DONE"; exit 1; }
T0=$(date +%s.%N); kill -ABRT "$S"; log "KILLED sales $S"
for _ in $(seq 120); do
  t=$(echo "$(date +%s.%N) - $T0" | bc)
  echo "$t sales=$(alive "$S") inventory=$(alive "$I") session=$(alive "${SESS%% *}") containers=$(containers)" >> "$OUT/watch.txt"
  sleep 0.5
done
log "AFTER inventory=$(alive "$I") session=$(alive "${SESS%% *}") containers=$(containers)"
cp "$D/.brickkit/local-session.log" "$OUT/local-session.log" 2>/dev/null  # secure restarts the session into this log
teardown; log "ALL-DONE"
