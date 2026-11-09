#!/usr/bin/env bash
R=/home/zhijie/Desktop/github/be-assembly-standard
OUT=$(dirname "$0")
echo $$ > $OUT/pid
. $R/dev/rebuild/experiment-scripts/accenv.sh > /dev/null 2>&1
. $R/dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1
export BE_ACC_PG_ADMIN=$BE_SDK_TEST_PG_ADMIN BE_ACC_NATS_URL=$BE_SDK_TEST_NATS_URL BE_ACC_S3_URL=$BE_SDK_TEST_S3_URL \
  BE_ACC_S3_ACCESS_KEY=$BE_SDK_TEST_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY=$BE_SDK_TEST_S3_SECRET_KEY PYTHONDONTWRITEBYTECODE=1
cd $R/tools/be-acceptance/conformance
uv run pytest -v -p no:cacheprovider tests/test_tiering_profile.py tests/test_manifests.py tests/test_probes.py > $OUT/pytest.log 2>&1
rc=$?
echo "TIERPROF ALL-DONE rc=$rc" >> $OUT/status.log
