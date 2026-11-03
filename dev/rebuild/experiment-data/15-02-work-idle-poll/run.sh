#!/usr/bin/env bash
# Idle cost of a member's background work, before (be-sdk-go alpha.49) and after (P7.23), paired and alternating, in
# performance power mode (restored on exit). Usage: run.sh <before binary> <after binary> <output file> [seconds] [pairs]
# [before label] [after label]
set -euo pipefail
before=$1 after=$2 out=$3 seconds=${4:-60} pairs=${5:-3} bl=${6:-before} al=${7:-after}
mode=$(powerprofilesctl get)
trap 'powerprofilesctl set "$mode"' EXIT
powerprofilesctl set performance
{
  echo "# $(date -Is) power mode: $(powerprofilesctl get) (was $mode); $(nproc) CPUs; load: $(cut -d' ' -f1-3 /proc/loadavg)"
  for i in $(seq "$pairs"); do
    "$before" -seconds "$seconds" -statistics -label "$bl-$i"
    "$after" -seconds "$seconds" -statistics -label "$al-$i"
  done
  echo "# $(date -Is) done; load: $(cut -d' ' -f1-3 /proc/loadavg)"
} > "$out" 2>&1
