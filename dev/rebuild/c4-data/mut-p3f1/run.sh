#!/bin/bash
# Runs the P3f-1 mutation check in the background; writes its PID and an outermost end marker.
D=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/c4-data/mut-p3f1
echo $$ > $D/pid
cd /home/zhijie/Desktop/github/be-assembly-standard/components/erp/finance
source ../../../dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
PYTHONDONTWRITEBYTECODE=1 python3 -u $D/mutate.py > $D/result.txt 2>&1
echo "P3F1-MUTATION-END exit=$?" >> $D/result.txt
