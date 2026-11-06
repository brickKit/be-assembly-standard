#!/bin/bash
T=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/foundations-04-data/t13; echo $$ > $T/authz37-mut.pid
cd /home/zhijie/Desktop/github/be-assembly-standard/components/infra/authz && . ../../../dev/rebuild/experiment-scripts/compenv.sh
python3 ../../../dev/rebuild/experiment-scripts/mutate.py $T/authz37-mutants.py $T/authz37-mutants.txt > $T/authz37-mut.log 2>&1
echo "AUTHZ37-MUT ALL-DONE rc=$?" >> $T/authz37-mut.log
