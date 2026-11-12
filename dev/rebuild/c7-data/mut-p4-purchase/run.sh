#!/bin/bash
# The purchase mutation round in the background (f-longrun); writes its pid first. MUT and OUT name another round.
D=/home/zhijie/Desktop/github/be-assembly-standard
M=$D/dev/rebuild/c7-data/mut-p4-purchase
echo $$ > $M/pid
cd $D/components/erp/purchase
source $D/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
python3 $D/dev/rebuild/experiment-scripts/mutate.py $M/${MUT:-mutants.py} $M/${OUT:-result.txt}
echo "MUTP4 ALL-DONE rc=$?"
