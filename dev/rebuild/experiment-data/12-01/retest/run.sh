#!/bin/bash
# step 12 re-test on the SDKs with P5.32, P3.10, P4.29: V1 (v1b.sh), then V2 with the new callers
X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts; O=$1
echo $$ > "$O/run.pid"
"$X/v1b.sh" "$O/v1b"
TESTS=compat/test_pairs.py "$X/runner12.sh" "$O/v2" D12-V2-go2 D12-V2-py2
echo "ALL-DONE $(date -Is)" >> "$O/run.log"
