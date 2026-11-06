#!/bin/bash
# T2a: parquet-go v0.32.0 against arrow-go v18.8.0 (bench/main.go), ROWS rows (default 1,000,000), ROUNDS rounds
# (default 5) alternating the two libraries, each a write then a read, every run its own process. The power profile is
# switched to performance for the run and restored at the end (also when stopped). Raw output: results.jsonl.
set -u
O=$(dirname "$(realpath "$0")"); D=${DATA:-/home/zhijie/data/t2a}; ROWS=${ROWS:-1000000}; ROUNDS=${ROUNDS:-5}
mkdir -p $D
PREV=$(powerprofilesctl get 2>/dev/null || echo unknown)
restore() { [ "$PREV" != unknown ] && powerprofilesctl set "$PREV"; }
trap restore EXIT
powerprofilesctl set performance 2>/dev/null
(cd $O/bench && go build -o $D/bench .) || exit 1
{
  echo "# $(date -u +%FT%TZ) power $(powerprofilesctl get) (was $PREV); $(go version); $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //'); $(nproc) cpus"
  echo "# parquet-go $(grep 'parquet-go/parquet-go ' $O/bench/go.mod | awk '{print $2}'), arrow-go $(grep 'apache/arrow-go/v18 ' $O/bench/go.mod | awk '{print $2}'); rows $ROWS, rounds $ROUNDS"
} > $O/results.jsonl
for r in $(seq 1 $ROUNDS); do
  for l in pq arrow; do
    for op in write read; do
      out=$($D/bench $l $op $ROWS $D/r-$l.parquet) || { echo "FAILED $l $op round $r"; exit 1; }
      echo "{\"round\":$r,${out#\{}" >> $O/results.jsonl
    done
  done
done
echo "# power at the end: $(powerprofilesctl get)" >> $O/results.jsonl
echo "T2A ALL-DONE"
