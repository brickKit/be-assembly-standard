#!/bin/bash
# T12: the suite's make probes with the Go probe 3.2.48 (be-sdk-go alpha.116); output in probes.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/probes.pid
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
export BE_ACC_PG_ADMIN=$BE_SDK_TEST_PG_ADMIN BE_ACC_NATS_URL=$BE_SDK_TEST_NATS_URL BE_ACC_S3_URL=$BE_SDK_TEST_S3_URL \
  BE_ACC_S3_ACCESS_KEY=$BE_SDK_TEST_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY=$BE_SDK_TEST_S3_SECRET_KEY PYTHONDONTWRITEBYTECODE=1
cd $R/tools/be-acceptance && make probes > $O/probes.log 2>&1
echo "PROBES ALL-DONE rc=$?" >> $O/probes.log
