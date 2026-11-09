#!/usr/bin/env bash
OUT=$1; mkdir -p $OUT; echo $$ > $OUT/pid
R=/home/zhijie/Desktop/github/be-assembly-standard
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
cd $R/tools/be-sdk-python
PYTHONDONTWRITEBYTECODE=1 uv run pytest -q -p no:cacheprovider > $OUT/unit.log 2>&1 && \
PYTHONDONTWRITEBYTECODE=1 uv run pytest -q -p no:cacheprovider -m integration > $OUT/it.log 2>&1
echo "SDKIT ALL-DONE rc=$?" >> $OUT/status.log
