#!/bin/bash
# C7 P4: the tools, then the shells, after the SDK unify to alpha.125. Output in run-p4-tools-shells.log.
O=$(dirname "$(realpath "$0")")
echo $$ > $O/run-p4-tools-shells.pid
bash $O/tools-p4/run.sh; tail -1 $O/tools-p4/run.out
grep -q "TOOLS ALL-DONE" $O/tools-p4/run.out || { echo "P4TS FAILED tools"; exit 1; }
bash $O/shells-p4.sh > $O/shells-p4.log 2>&1; tail -1 $O/shells-p4.log
grep -q "SHELLS ALL-DONE" $O/shells-p4.log || { echo "P4TS FAILED shells"; exit 1; }
echo "P4TS ALL-DONE"
