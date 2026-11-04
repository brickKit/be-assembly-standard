#!/bin/bash
# Foundations item 3, T6's real run (infra/authz 3.0.20: dispositions, recovery, the install claim by a one-time code): F3-S (every member alone), then F3-X (be/go-infra 3.0.45), each from
# an empty database through cell-chain.sh (create, prepare, build, up, install claim, seeds twice, L3), then down.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
for c in F3-S F3-X; do
  KEEP_UP=0 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh $c $O/$c > $O/$c.log 2>&1
  echo "$c rc=$?" >> $O/summary.txt
  # a failed stage leaves the cell up: stop it, or the next cell cannot bind its ports
  (cd $R/dev/rebuild/experiment-cells/$c && brickkit down > /dev/null 2>&1)
done
echo done >> $O/summary.txt
