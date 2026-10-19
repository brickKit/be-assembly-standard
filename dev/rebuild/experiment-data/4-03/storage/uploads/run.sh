#!/bin/bash
# Upload timelines: RustFS, then SeaweedFS, then RustFS back as the default. Idle 120 s, then 50 PUTs a second of
# 100 KiB for 600 s, the storage CPU read every second. Records and restores the power profile itself.
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
export BE_ACC_CONFORMANCE=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance
O=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/stbench; R=/home/zhijie/Desktop/github/be-assembly-standard
before=$(powerprofilesctl get); echo "$before" > $O/power-before.txt
restore() { powerprofilesctl set "$before"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> $O/status.log; }
trap restore EXIT
powerprofilesctl set performance; echo "POWER $before -> $(powerprofilesctl get) $(date -Is)" >> $O/status.log
healthy() { for i in $(seq 1 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' $1 2>/dev/null)" = healthy ] && return 0; sleep 2; done; return 1; }
bench() {
  echo "PHASE $1 $(date -Is)" >> $O/status.log
  (cd $BE_ACC_CONFORMANCE && uv run python $O/stbench.py $1 $O/$1.json --idle 120 --seconds 600) > $O/$1.log 2>&1
  [ -s $O/$1.json ] || { echo "END exit=1 phase=$1 $(date -Is)" >> $O/status.log; exit 1; }
  echo "DONE $1 $(tail -1 $O/$1.log)" >> $O/status.log
}
bench be-rustfs
cd $R; docker stop be-rustfs >> $O/switch.log 2>&1; make seaweedfs-up >> $O/switch.log 2>&1; healthy be-seaweedfs || { echo "END exit=1 seaweedfs not healthy" >> $O/status.log; exit 1; }
bench be-seaweedfs
cd $R; make seaweedfs-down >> $O/switch.log 2>&1; docker start be-rustfs >> $O/switch.log 2>&1; healthy be-rustfs || { echo "END exit=1 rustfs not healthy" >> $O/status.log; exit 1; }
echo "END exit=0 $(date -Is)" >> $O/status.log
