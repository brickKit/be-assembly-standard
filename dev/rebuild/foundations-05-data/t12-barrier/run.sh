#!/usr/bin/env bash
# The write barrier's pinned search_path, measured in pairs (foundations item 5, T12): 50,000 inserts through a
# trigger doing the barrier's member lookup, f_plain and f_pinned alternating (ABBA within each pair, so order and
# drift cancel), plus the same inserts without a trigger; two batches of the same code to show the run-to-run spread.
# Switches the power profile to performance and restores it on exit (also when stopped). Usage: run.sh <out dir>
set -uo pipefail
OUT="${1:?out dir}"; mkdir -p "$OUT"; echo $$ > "$OUT/pid"
HERE="$(cd "$(dirname "$0")" && pwd)"
PAIRS="${PAIRS:-12}"
old="$(powerprofilesctl get)"
restore() { powerprofilesctl set "$old"; echo "power restored to $old $(date -Is)" >> "$OUT/status.log"; }
trap restore EXIT
trap 'exit 130' INT TERM
powerprofilesctl set performance
{
  echo "BARRIER START $(date -Is) power=$(powerprofilesctl get) (was $old) pairs=$PAIRS"
  echo "load: $(cat /proc/loadavg)"
  echo "containers: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
} >> "$OUT/status.log"
ps -eo pcpu,pid,comm --sort=-pcpu | head -15 > "$OUT/top-start.txt"
psql() { docker exec -i be-postgres psql -U postgres -X -q -At -v ON_ERROR_STOP=1 "$@"; }
psql -c "SELECT version()" > "$OUT/version.txt"
insert="INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i"
# one timed insert under the given trigger function (none = no trigger); prints the ms
one() {
  local fn="$1" sql="SET search_path = bb; DROP TRIGGER IF EXISTS g ON t; TRUNCATE t;"
  [ "$fn" != none ] && sql+=" CREATE TRIGGER g BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION $fn();"
  psql -c "$sql" >/dev/null 2>>"$OUT/psql.log" || return 1
  printf 'SET search_path = bb;\n\\timing on\n%s;\n' "$insert" | psql 2>&1 | sed -n 's/^Time: \([0-9.]*\) ms.*/\1/p' | tail -1
}
for batch in 1 2; do
  psql < "$HERE/setup.sql" >/dev/null 2>>"$OUT/psql.log" || { echo "BARRIER FAILED setup" >> "$OUT/status.log"; exit 1; }
  for w in 1 2 3; do one f_plain >/dev/null; one f_pinned >/dev/null; done   # warm up
  for p in $(seq 1 "$PAIRS"); do
    for fn in f_plain f_pinned f_pinned f_plain none; do
      ms="$(one $fn)" || { echo "BARRIER FAILED batch=$batch pair=$p fn=$fn" >> "$OUT/status.log"; exit 1; }
      echo "$batch $p $fn $ms" >> "$OUT/raw.txt"
    done
    echo "pair batch=$batch $p/$PAIRS $(date -Is) power=$(powerprofilesctl get)" >> "$OUT/status.log"
  done
  psql -c "DROP SCHEMA bb CASCADE" >/dev/null 2>>"$OUT/psql.log"
done
echo "load at end: $(cat /proc/loadavg)" >> "$OUT/status.log"
python3 "$HERE/summary.py" "$OUT/raw.txt" > "$OUT/summary.txt"
echo "BARRIER ALL-DONE $(date -Is)" >> "$OUT/status.log"
