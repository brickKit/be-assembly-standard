#!/bin/bash
# The install claim of T9's F3-S timed out once (AUTHORIZATION_VIEW_EXPIRED for 60 s): F3-S brought up to the secure
# stage from an empty database N times; the first failure stops the loop with the cell left up for its logs.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/foundations-03-data/t9-cells/loop; N=${1:-6}
mkdir -p $O; echo $$ > $O/run.pid; : > $O/summary.txt
for i in $(seq 1 $N); do
  rm -rf $O/run$i
  KEEP_UP=1 SEED=0 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh F3-S $O/run$i > $O/run$i.log 2>&1; rc=$?
  secs=$(sed -n 's/^STAGE 5 secure END exit=[0-9]* secs=//p' $O/run$i/status.log)
  echo "run$i rc=$rc secure_secs=$secs" >> $O/summary.txt
  if [ $rc -ne 0 ]; then
    for c in $(docker ps --format '{{.Names}}' | grep brickkit-f3-s); do docker logs $c > $O/run$i/$c.container.log 2>&1; done
    echo "LOOP STOPPED-AT-FAILURE" >> $O/summary.txt; exit 1
  fi
  (cd $R/dev/rebuild/experiment-cells/F3-S && brickkit down > /dev/null 2>&1)
done
echo "LOOP ALL-DONE" >> $O/summary.txt
