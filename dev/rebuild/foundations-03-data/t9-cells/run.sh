#!/bin/bash
# Foundations item 3, T9's real run (second attempt: the first one's install claim waited 60 s for a view and failed once, not reproduced in 7 more runs, loop/) (infra/iam-casdoor 3.0.22, infra/authz 3.0.26; be/go-infra 3.0.49 on be-sdk-go
# alpha.76; suite 1.0.44): F3-S (every member alone), then F3-X (be/go-infra 3.0.49), each from an empty database
# through cell-chain.sh (create, prepare, build, up, install claim, seeds twice, L3), then down.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/run.pid; : > $O/summary.txt
for c in F3-S F3-X; do
  KEEP_UP=0 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh $c $O/$c > $O/$c.log 2>&1
  rc=$?; echo "$c rc=$rc" >> $O/summary.txt
  # a failed stage leaves the cell up: keep every container's log first (the first run lost them), then stop it, or
  # the next cell cannot bind its ports
  if [ $rc -ne 0 ]; then
    lc=$(echo $c | tr 'A-Z' 'a-z')
    for n in $(docker ps --format '{{.Names}}' | grep "brickkit-$lc-"); do docker logs $n > $O/$c/$n.container.log 2>&1; done
  fi
  (cd $R/dev/rebuild/experiment-cells/$c && brickkit down > /dev/null 2>&1)
done
echo "T9CELLS ALL-DONE" >> $O/summary.txt
