#!/usr/bin/env bash
# T2b: the Parquet candidates for be-sdk-python's cold tier, measured in rounds that alternate the candidates (one fresh
# process per candidate per round: 100,000 rows, 5 timed write+read pairs after a warm-up). Switches the power profile
# to performance and restores it on exit (also when stopped). Usage: run.sh <out dir> ; ROUNDS (default 8).
set -u
OUT="${1:?out dir}"; mkdir -p "$OUT"; echo $$ > "$OUT/run.pid"
HERE="$(dirname "$(realpath "$0")")"
PY="${PY:?the venv python with pyarrow, polars, duckdb}"
ROUNDS="${ROUNDS:-8}"
old="$(powerprofilesctl get)"
trap 'powerprofilesctl set "$old"; echo "PQBENCH power restored to $old" >> "$OUT/status.log"' EXIT
powerprofilesctl set performance
{
  echo "PQBENCH START $(date -Is) power=$(powerprofilesctl get) (was $old) rounds=$ROUNDS"
  "$PY" -c 'import pyarrow, polars, duckdb, sys; print("versions", sys.version.split()[0], "pyarrow", pyarrow.__version__, "polars", polars.__version__, "duckdb", duckdb.__version__)'
  uname -r; nproc; grep "model name" /proc/cpuinfo | head -1
} >> "$OUT/status.log" 2>&1
for r in $(seq 1 "$ROUNDS"); do
  # rotate the order each round so no candidate always runs first
  case $((r % 3)) in 0) order="pyarrow polars duckdb";; 1) order="polars duckdb pyarrow";; 2) order="duckdb pyarrow polars";; esac
  for c in $order; do
    echo "PQBENCH round=$r candidate=$c power=$(powerprofilesctl get) load=$(cut -d' ' -f1 /proc/loadavg)" >> "$OUT/status.log"
    "$PY" -I "$HERE/bench.py" "$c" 100000 5 >> "$OUT/raw.jsonl" 2>> "$OUT/errors.log" || { echo "PQBENCH FAILED round=$r candidate=$c" >> "$OUT/status.log"; exit 1; }
  done
done
echo "PQBENCH ALL-DONE $(date -Is)" >> "$OUT/status.log"
