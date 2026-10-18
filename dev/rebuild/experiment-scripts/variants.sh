#!/bin/bash
# baseline, +sniffio, +sniffio+httptools; HTTP and gRPC each; the probe's venv restored at the end
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad
P=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/probes/py
C=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance
cd /home/zhijie/Desktop/github/be-assembly-standard && source $S/accenv.sh
OUT=$S/prof/variants; rm -rf "${OUT:?}"; mkdir -p $OUT; cd $OUT
measure() { for surface in http grpc; do KEEP_VENV=1 timeout 300 uv run --project $C python $S/prof/cpu_per_request.py $OUT "$1" $surface 100 20 2>&1 | grep '^{' >> $OUT/results.jsonl || echo "{\"label\": \"$1\", \"surface\": \"$surface\", \"failed\": true}" >> $OUT/results.jsonl; done; }
(cd $P && uv sync --frozen --no-dev -q)
measure baseline
VIRTUAL_ENV=$P/.venv uv pip install -q --python $P/.venv/bin/python sniffio
measure sniffio
VIRTUAL_ENV=$P/.venv uv pip install -q --python $P/.venv/bin/python httptools
measure sniffio+httptools
(cd $P && uv sync --frozen --no-dev -q)
echo DONE >> $OUT/results.jsonl
