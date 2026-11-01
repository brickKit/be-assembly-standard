#!/bin/bash
# Step 12, G5 (P1.21): the real-machine check of the a35 release. D12-H-a35 as the chain check (seed data, L3, the
# department projection), then D12-py-a35 (the Python probes in be/py-render 3.0.31, the pair tests). One runner12.sh per
# cell, each in its own directory; this script's own status.log gets the outermost mark P121 ALL-DONE.
# Usage: p121check.sh <out>
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"; LOG=$OUT/status.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
say "P121 START"
TESTS=compat/test_projection.py "$X/runner12.sh" "$OUT/h" D12-H-a35; say "P121 D12-H-a35 $(grep -h 'TESTS\|FAILED' "$OUT/h/status.log" | tr '\n' ' ')"
TESTS=compat/test_pairs.py "$X/runner12.sh" "$OUT/py" D12-py-a35; say "P121 D12-py-a35 $(grep -h 'TESTS\|FAILED' "$OUT/py/status.log" | tr '\n' ' ')"
say "P121 ALL-DONE"
