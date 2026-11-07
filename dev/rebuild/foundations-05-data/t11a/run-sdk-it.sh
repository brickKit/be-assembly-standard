#!/bin/bash
# be-sdk-go's make test-integration before releasing alpha.116; output in sdk-it.log ("SDKIT ALL-DONE rc=" last).
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/sdk-it.pid
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
cd $R/tools/be-sdk-go && make test-integration > $O/sdk-it.log 2>&1
echo "SDKIT ALL-DONE rc=$?" >> $O/sdk-it.log
