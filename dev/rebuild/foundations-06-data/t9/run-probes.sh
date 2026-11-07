#!/bin/bash
# T9: make probes (Python probes 3.2.49 on be-sdk-python a59, the recovery checks), output in probes.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/probes.pid
set -a; . $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1; set +a
export BE_ACC_PG_ADMIN=$BE_SDK_TEST_PG_ADMIN BE_ACC_NATS_URL=$BE_SDK_TEST_NATS_URL BE_ACC_S3_URL=$BE_SDK_TEST_S3_URL \
  BE_ACC_S3_ACCESS_KEY=$BE_SDK_TEST_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY=$BE_SDK_TEST_S3_SECRET_KEY PYTHONDONTWRITEBYTECODE=1
cd $R/tools/be-acceptance && make probes > $O/probes.log 2>&1
echo "PROBES-T9 EXIT $?" >> $O/probes.log
