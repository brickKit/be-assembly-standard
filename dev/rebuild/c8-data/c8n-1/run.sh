#!/bin/bash
echo $$ > "$1/pid"
cd /home/zhijie/Desktop/github/be-assembly-standard
bash dev/rebuild/experiment-scripts/cell-chain.sh C8-N "$1" > "$1/chain.out" 2>&1
echo "C8N RUN-END exit=$?" >> "$1/status.log"
