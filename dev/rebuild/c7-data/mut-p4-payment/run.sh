#!/bin/bash
# The payment mutation round in the background (f-longrun); writes its pid first. MUT and OUT name another round.
D=/home/zhijie/Desktop/github/be-assembly-standard
M=$D/dev/rebuild/c7-data/mut-p4-payment
echo $$ > $M/pid
cd $D/components/erp/payment
source $D/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
python3 $D/dev/rebuild/experiment-scripts/mutate.py $M/${MUT:-mutants.py} $M/${OUT:-result.txt}
echo "MUTP4PAY ALL-DONE rc=$?"
