#!/bin/bash
# Python 3.15 with the JIT off and on: the uvicorn echo (200/s, 1000/s) and the probes' big-event path (50/s).
S=<scratch>
C=<repo>/tools/be-acceptance/conformance
source $S/accenv.sh
OUT=$S/prof/jit; rm -f $OUT/results.jsonl
for jit in 0 1; do
  cd /tmp && PYTHON_JIT=$jit SERVERS=uvicorn timeout 300 $S/venv315/bin/python $S/prof/asgi/bench.py $S/venv315/bin/python 10 200 1000 | sed "s/^{/{\"jit\": $jit, /" >> $OUT/results.jsonl
  D=$OUT/big-$jit; rm -rf "${D:?}"; mkdir -p $D; cd $D
  PYTHON_JIT=$jit PROFILE=0 PROBE_PYTHON=$S/venv315/bin/python timeout 300 uv run --project $C python $S/prof/profile_big.py $D 50 20 > $D/run.log 2>&1
  echo "{\"jit\": $jit, \"big_event\": $(grep '^{' $D/run.log | tail -1 || echo null)}" >> $OUT/results.jsonl
done
echo DONE >> $OUT/results.jsonl
