#!/usr/bin/env bash
# usage: run.sh <out dir> <minutes>
OUT=$1; MIN=$2
R=/home/zhijie/Desktop/github/be-assembly-standard
mkdir -p $OUT; echo $$ > $OUT/pid
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
cd $R/tools/be-sdk-python
SIM_MINUTES=$MIN SIM_REPLICA_LOG=$OUT/replicas.log PYTHONDONTWRITEBYTECODE=1 uv run pytest -q -s -p no:cacheprovider -m simulation tests/sim/test_tiering_simulation.py > $OUT/sim.log 2>&1
echo "TIERSIM ALL-DONE rc=$?" >> $OUT/status.log
