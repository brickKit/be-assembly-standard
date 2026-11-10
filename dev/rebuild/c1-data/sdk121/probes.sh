#!/bin/bash
# C1 E6: the probes' tests (make probes) for the Go probe 3.2.52 on be-sdk-go alpha.121.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c1-data/sdk121
echo $$ > $O/probes.pid
. $R/dev/rebuild/experiment-scripts/accenv.sh >/dev/null 2>&1
export PYTHONDONTWRITEBYTECODE=1
cd $R/tools/be-acceptance && make probes
echo "PROBES RUN-END $?"
