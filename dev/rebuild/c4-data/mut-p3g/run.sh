#!/bin/bash
# P3g: every step's mutation script again on the final code, one after another; one line per script's end.
D=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/c4-data
OUT=$D/mut-p3g
echo $$ > $OUT/pid
cd /home/zhijie/Desktop/github/be-assembly-standard/components/erp/finance
source ../../../dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
: > $OUT/all.txt
for s in p3b p3c p3d p3e p3f1 p3f2 p3f3; do
  echo "=== $s" >> $OUT/all.txt
  PYTHONDONTWRITEBYTECODE=1 python3 -u $D/mut-$s/mutate.py >> $OUT/all.txt 2>&1
  echo "SCRIPT-END $s exit=$?" >> $OUT/all.txt
done
echo "P3G-ALL-END" >> $OUT/all.txt
