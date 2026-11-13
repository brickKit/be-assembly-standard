#!/bin/bash
# tools.sh, then shells.sh (the shells take the probe tools.sh releases). Writes $$ to run.pid; "RUN ALL-DONE" or
# "RUN FAILED" in run.out.
O=$(dirname "$(realpath "$0")"); echo $$ > $O/run.pid
bash $O/tools.sh > $O/tools.log 2>&1 && grep -q "TOOLS ALL-DONE" $O/run.out && bash $O/shells.sh > $O/shells.log 2>&1 && grep -q "SHELLS ALL-DONE" $O/shells.log
if [ $? -eq 0 ]; then echo "RUN ALL-DONE" >> $O/run.out; else echo "RUN FAILED" >> $O/run.out; fi
