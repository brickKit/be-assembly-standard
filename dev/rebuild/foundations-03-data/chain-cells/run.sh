#!/bin/bash
# Foundations item 3, the chain upgrade's real run: F3-S (every member alone), then F3-X (be/go-infra 3.0.41), each from
# an empty database through cell-chain.sh (create, prepare, build, up, install claim, seeds twice, L3), then down.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
for c in F3-S F3-X; do
  KEEP_UP=0 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh $c $O/$c > $O/$c.log 2>&1
  echo "$c rc=$?" >> $O/summary.txt
done
echo done >> $O/summary.txt
