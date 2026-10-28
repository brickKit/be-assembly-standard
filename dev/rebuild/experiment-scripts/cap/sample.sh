#!/bin/bash
# Every INTERVAL seconds (5), one line of a cgroup's memory state, until killed: time, memory.current, swap.current,
# the memory.events counters (high, max, oom, oom_kill) and memory.pressure (some and full, avg10). Reads only the
# cgroup v2 files, no root needed.
# Usage: sample.sh <out.tsv> [cgroup directory, default /sys/fs/cgroup/be-cap.slice]
set -u
OUT=$1; G=${2:-/sys/fs/cgroup/be-cap.slice}; I=${INTERVAL:-5}
echo -e "time\tcurrent_mib\tswap_mib\thigh\tmax\toom\toom_kill\tsome_avg10\tfull_avg10" > "$OUT"
while true; do
  ev() { awk -v k="$1" '$1 == k {print $2}' "$G/memory.events"; }
  pr() { awk -v k="$1" '$1 == k {split($2, a, "="); print a[2]}' "$G/memory.pressure"; }
  echo -e "$(date -Is)\t$(( $(cat "$G/memory.current") / 1048576 ))\t$(( $(cat "$G/memory.swap.current" 2>/dev/null || echo 0) / 1048576 ))\t$(ev high)\t$(ev max)\t$(ev oom)\t$(ev oom_kill)\t$(pr some)\t$(pr full)" >> "$OUT"
  sleep "$I"
done
