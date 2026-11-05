#!/bin/bash
D=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/foundations-04-data/t11/t11b; echo $$ > $D/iam-mut.pid
cd /home/zhijie/Desktop/github/be-assembly-standard/components/infra/iam-casdoor
. ../../../dev/rebuild/experiment-scripts/itenv.sh; . ../../../dev/rebuild/experiment-scripts/iamenv.sh
python3 ../../../dev/rebuild/experiment-scripts/mutate.py $D/iam-mutants.py $D/iam-mutants.txt > $D/iam-mut.log 2>&1
echo "IAM-MUT ALL-DONE rc=$?" >> $D/iam-mut.log
