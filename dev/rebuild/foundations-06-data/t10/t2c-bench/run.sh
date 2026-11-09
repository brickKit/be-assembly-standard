#!/usr/bin/env bash
# T2c: the event loop's stall and the CPU cost of the tiering's compute on the loop, in a thread and in a worker
# process, in rounds that alternate the modes (one fresh process per mode per round: 20,000 rows, 5 reps of the seal,
# copy and read steps after a warm-up). Switches the power profile to performance and restores it on exit (also when
# stopped). Usage: PY=<be-sdk-python's venv python> run.sh <out dir> ; ROUNDS (default 8), ROWS (default 20000),
# MODES (default: loop, thread and process in rotation; given: those modes alternated).
set -u
OUT="${1:?out dir}"; mkdir -p "$OUT"; echo $$ > "$OUT/run.pid"
HERE="$(dirname "$(realpath "$0")")"
PY="${PY:?the python of the be-sdk-python environment (besdk, pyarrow)}"
ROUNDS="${ROUNDS:-8}"; ROWS="${ROWS:-20000}"
old="$(powerprofilesctl get)"
trap 'powerprofilesctl set "$old"; echo "T2C power restored to $old" >> "$OUT/status.log"' EXIT
powerprofilesctl set performance
{
  echo "T2C START $(date -Is) power=$(powerprofilesctl get) (was $old) rounds=$ROUNDS rows=$ROWS"
  "$PY" -c 'import sys, pyarrow; from importlib.metadata import version; print("versions", sys.version.split()[0], "be-sdk", version("be-sdk"), "pyarrow", pyarrow.__version__)'
  uname -r; nproc; grep "model name" /proc/cpuinfo | head -1
} >> "$OUT/status.log" 2>&1
for r in $(seq 1 "$ROUNDS"); do
  if [ -n "${MODES:-}" ]; then  # e.g. MODES="thread thread-chunk": alternated, the first first in odd rounds
    set -- $MODES; order="$*"; [ $((r % 2)) -eq 0 ] && order="$(printf '%s\n' $MODES | tac | tr '\n' ' ')"
  else
    case $((r % 3)) in 0) order="loop thread process";; 1) order="thread process loop";; 2) order="process loop thread";; esac
  fi
  for m in $order; do
    echo "T2C round=$r mode=$m power=$(powerprofilesctl get) load=$(cut -d' ' -f1 /proc/loadavg)" >> "$OUT/status.log"
    "$PY" -I "$HERE/bench.py" "$m" "$ROWS" 5 >> "$OUT/raw.jsonl" 2>> "$OUT/errors.log" || { echo "T2C FAILED round=$r mode=$m" >> "$OUT/status.log"; exit 1; }
  done
done
echo "T2C ALL-DONE $(date -Is)" >> "$OUT/status.log"
