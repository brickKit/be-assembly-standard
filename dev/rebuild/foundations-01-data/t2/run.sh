#!/bin/bash
# T2: the whole integration runs (Go SDK, Python SDK, acceptance probes) twice; a snapshot of the shared test
# resources before and after each round. Not a performance measurement: the power mode is left as it is.
S=$(dirname "$0"); R=/home/zhijie/Desktop/github/be-assembly-standard
source $R/dev/rebuild/experiment-scripts/itenv.sh
export BE_ACC_PG_ADMIN=$BE_SDK_TEST_PG_ADMIN BE_ACC_NATS_URL=$BE_SDK_TEST_NATS_URL BE_ACC_S3_URL=$BE_SDK_TEST_S3_URL \
  BE_ACC_S3_ACCESS_KEY=$BE_SDK_TEST_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY=$BE_SDK_TEST_S3_SECRET_KEY
out=${1:-$S/runs}; mkdir -p $out
echo "power mode: $(powerprofilesctl get 2>/dev/null)" > $out/power.txt
$S/snapshot.sh > $out/0-before.txt
for round in 1 2; do
  (cd $R/tools/be-sdk-go && go test -count=1 -p 1 -tags integration ./... > $out/$round-go.log 2>&1; echo "exit $?" >> $out/$round-go.log)
  $S/snapshot.sh > $out/$round-after-go.txt
  (cd $R/tools/be-sdk-python && uv run pytest -q -m integration > $out/$round-py.log 2>&1; echo "exit $?" >> $out/$round-py.log)
  $S/snapshot.sh > $out/$round-after-py.txt
  (cd $R/tools/be-acceptance/conformance && uv run pytest -q tests/test_probes.py tests/test_profile.py > $out/$round-acc.log 2>&1; echo "exit $?" >> $out/$round-acc.log)
  $S/snapshot.sh > $out/$round-after-acc.txt
done
echo done > $out/DONE
