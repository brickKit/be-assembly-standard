#!/bin/bash
# step 12: V6 (two Go shells on different SDKs, the pair tests) then V3 (the business chain, the projection test)
X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts; O=$1
echo $$ > "$O/run.pid"
TESTS=compat/test_pairs.py "$X/runner12.sh" "$O/v6" D12-V6
TESTS=compat/test_projection.py "$X/runner12.sh" "$O/v3" D12-V3
echo "ALL-DONE $(date -Is)" >> "$O/run-v6-v3.log"
