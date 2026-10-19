#!/bin/bash
# Storage backends, second pass (with the storage CPU read on both): D-S big events on SeaweedFS, then on RustFS (the
# default, left running). Records the power profile itself and restores it on any exit; a phase without its 8 results
# (4 edges x 2 loads) stops the run.
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
O=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/storage2; R=/home/zhijie/Desktop/github/be-assembly-standard
before=$(powerprofilesctl get); echo "$before" > $O/power-before.txt
restore() { powerprofilesctl set "$before"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> $O/status.log; }
trap restore EXIT
powerprofilesctl set performance; echo "POWER $before -> $(powerprofilesctl get) $(date -Is)" >> $O/status.log
healthy() { for i in $(seq 1 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' $1 2>/dev/null)" = healthy ] && return 0; sleep 2; done; return 1; }
phase() {
  echo "PHASE $1 $(date -Is)" >> $O/status.log
  (cd $R/tools/be-acceptance/conformance && uv run python -m cells campaign $R/dev/rebuild/experiment-cells/campaign-storage.yaml $O/$1 > $O/$1.log 2>&1)
  n=$(find $O/$1 -name result.json | wc -l)
  [ "$n" -eq 8 ] || { echo "END exit=1 phase=$1 results=$n $(date -Is)" >> $O/status.log; exit 1; }
}
cd $R; docker stop be-rustfs >> $O/switch.log 2>&1; make seaweedfs-up >> $O/switch.log 2>&1; healthy be-seaweedfs || { echo "END exit=1 seaweedfs not healthy" >> $O/status.log; exit 1; }
phase seaweedfs
cd $R; make seaweedfs-down >> $O/switch.log 2>&1; docker start be-rustfs >> $O/switch.log 2>&1; healthy be-rustfs || { echo "END exit=1 rustfs not healthy" >> $O/status.log; exit 1; }
phase rustfs
echo "END exit=0 $(date -Is)" >> $O/status.log
