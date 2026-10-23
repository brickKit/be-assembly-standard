#!/usr/bin/env bash
# Watches cell-full.sh every 30 s: each finished phase, problems (a FAILED phase, a container unhealthy or exited non-zero,
# no new output for 10 min, the runner gone), a progress line every 5 minutes, the end.
CELL=$1; LOG=$2; P=$(echo "$CELL" | tr 'A-Z' 'a-z'); start=$(date +%s); last=$start; seen=0; lsize=0; stall=0
while true; do
  sleep 30; now=$(date +%s)
  n=$(grep -cE -- "-(OK|FAILED)" $LOG 2>/dev/null); n=${n:-0}
  if [ "$n" -gt "$seen" ]; then grep -E -- "-(OK|FAILED)" $LOG | tail -n $((n-seen)) | sed "s/^/$CELL: /"; seen=$n; fi
  if grep -q DONE $LOG 2>/dev/null; then echo "$CELL: run finished ($(( (now-start)/60 )) min)"; exit 0; fi
  phase=$(grep -- "-START" $LOG | tail -1 | cut -d- -f1)
  if [ "$phase" != "create" ] && [ "$phase" != "build" ] && [ "$phase" != "profile" ]; then
    bad=$(docker ps -a --filter "name=brickkit-$P-" --format '{{.Names}} {{.Status}}' | grep -vE "\(healthy\)|migration.*Exited \(0\)|\(health: starting\)| Created$" | head -3)
    [ -n "$bad" ] && echo "$CELL PROBLEM ($phase): $bad"
  fi
  size=$(du -cb $LOG* 2>/dev/null | tail -1 | cut -f1)
  if [ "$size" = "$lsize" ]; then stall=$((stall+30)); else stall=0; lsize=$size; fi
  [ $stall -ge 600 ] && { echo "$CELL PROBLEM: no new output for 10 min in $phase"; stall=0; }
  pgrep -f "cell-full.sh $CELL" >/dev/null || { grep -q DONE $LOG || { echo "$CELL PROBLEM: runner gone without DONE"; exit 1; }; }
  if [ $((now-last)) -ge 300 ]; then echo "$CELL progress: $(( (now-start)/60 )) min, phase $phase ($seen phases done)"; last=$now; fi
done
