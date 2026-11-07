#!/bin/bash
# Layout L6: the business chain from an empty database in two cells (L6-S every member alone, L6-H the Go members in
# shells), each with cell-chain.sh (create, prepare, build, up, secure, seeds twice, L3), the cell taken down after.
# Output: <cell>/ per cell (status.log and the stages' logs), summary.txt with "L6 ALL-DONE" last.
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/run.pid; : > $O/summary.txt
export PYTHONDONTWRITEBYTECODE=1
BIN=$(mktemp -d)  # be-ops built from source, outside the repository (no build output in it); left in /tmp
(cd $R/tools/be-ops && CGO_ENABLED=0 go build -o $BIN/be-ops ./cmd/be-ops) || { echo "be-ops build failed" >> $O/summary.txt; echo "L6 ALL-DONE" >> $O/summary.txt; exit 1; }
export BE_OPS=$BIN/be-ops  # a secured cell's certificates come from its issuer (prepare.py)
for C in ${CELLS:-L6-S L6-H}; do
  echo "$C BEGIN $(date -u +%H:%M:%S)" >> $O/summary.txt
  KEEP_UP=0 $R/dev/rebuild/experiment-scripts/cell-chain.sh $C $O/$C; rc=$?
  echo "$C END rc=$rc $(date -u +%H:%M:%S)" >> $O/summary.txt
done
echo "L6 ALL-DONE" >> $O/summary.txt
