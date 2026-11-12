#!/bin/bash
echo $$ > "$1/pid"
cd /home/zhijie/Desktop/github/be-assembly-standard/components/infra/notification
source ../../../dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
PYTHONDONTWRITEBYTECODE=1 python3 ../../../dev/rebuild/experiment-scripts/mutate.py "$1/mutants.py" "$1/result.txt" > "$1/progress.log" 2>&1
echo "MUT-NT ALL-DONE exit=$?" >> "$1/progress.log"
