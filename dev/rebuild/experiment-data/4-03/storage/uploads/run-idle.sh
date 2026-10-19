#!/bin/bash
# RustFS idle CPU with 20 000 objects held; records and restores the power profile itself.
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
export BE_ACC_CONFORMANCE=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance
O=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/stbench
before=$(powerprofilesctl get)
trap 'powerprofilesctl set "$before"; echo "POWER restored $(powerprofilesctl get) $(date -Is)" >> $O/idle-status.log' EXIT
powerprofilesctl set performance; echo "POWER $before -> $(powerprofilesctl get) $(date -Is)" >> $O/idle-status.log
(cd $BE_ACC_CONFORMANCE && uv run python $O/idlefull.py be-rustfs $O/rustfs-idlefull.json) > $O/idle.log 2>&1
echo "END exit=$? $(tail -1 $O/idle.log) $(date -Is)" >> $O/idle-status.log
