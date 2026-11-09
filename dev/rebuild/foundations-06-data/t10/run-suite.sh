#!/usr/bin/env bash
OUT=$(dirname "$0"); echo $$ > $OUT/pid
R=/home/zhijie/Desktop/github/be-assembly-standard
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
export BE_ACC_PG_ADMIN=$BE_SDK_TEST_PG_ADMIN BE_ACC_NATS_URL=$BE_SDK_TEST_NATS_URL BE_ACC_S3_URL=$BE_SDK_TEST_S3_URL \
  BE_ACC_S3_ACCESS_KEY=$BE_SDK_TEST_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY=$BE_SDK_TEST_S3_SECRET_KEY PYTHONDONTWRITEBYTECODE=1
cd $R/tools/be-acceptance
make check > $OUT/check.log 2>&1 && make probes > $OUT/probes.log 2>&1
echo "ACC ALL-DONE rc=$?" >> $OUT/status.log
