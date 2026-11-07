#!/usr/bin/env bash
echo $$ > "$(dirname "$0")/mutants-t4a.pid"
cd /home/zhijie/Desktop/github/be-assembly-standard
set -a; . dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1; set +a
cd tools/be-sdk-python
python3 ../../dev/rebuild/experiment-scripts/mutate.py ../../dev/rebuild/foundations-06-data/t4/mutants-t4a.py \
  ../../dev/rebuild/foundations-06-data/t4/mutants-t4a.txt > ../../dev/rebuild/foundations-06-data/t4/mutants-t4a.log 2>&1
echo "MUTANTS-T4A ALL-DONE rc=$?" >> ../../dev/rebuild/foundations-06-data/t4/mutants-t4a.log
