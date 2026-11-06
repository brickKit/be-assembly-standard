#!/bin/bash
# T11d's measurement run: the power mode switched to performance for the run and put back after it (also when stopped);
# a smoke at a small size first, then the sizes asked. Usage: run.sh <out dir> <rounds> <MB> [<MB> ...]
O=$1 ROUNDS=$2; shift 2
mkdir -p "$O"; echo $$ > "$O/run.pid"
WAS=$(powerprofilesctl get); echo "power mode was $WAS" > "$O/power.txt"
trap 'powerprofilesctl set "$WAS"; echo "power mode back to $WAS" >> "$O/power.txt"' EXIT
powerprofilesctl set performance; echo "power mode during the run: $(powerprofilesctl get)" >> "$O/power.txt"
X=$(dirname "$(realpath "$0")")
for mb in "$@"; do
  bash "$X/bench.sh" "$O" "$mb" "$ROUNDS" >> "$O/bench.log" 2>&1 || { echo "BENCH FAILED $mb" >> "$O/bench.log"; break; }
done
echo "T11D ALL-DONE" >> "$O/bench.log"
