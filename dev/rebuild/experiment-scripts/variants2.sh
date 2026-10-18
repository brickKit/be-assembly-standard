#!/bin/bash
# The Python acceleration experiment (step 4 follow-up), each at 100/s for HTTP and gRPC outbound:
#   a7             the released SDK
#   uvloop-off     branch perf/uvloop without uvloop installed: must match a7 (the branch alone changes nothing)
#   uvloop         branch perf/uvloop with uvloop
#   aiohttp        branch perf/aiohttp (outbound HTTP on aiohttp), asyncio loop
#   both           branch perf/both with uvloop
# Then the SDK's integration tests on perf/aiohttp (asyncio) and on perf/both under uvloop (grpc.aio compatibility).
# The probe's environment and the SDK checkout are restored at the end.
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad
P=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/probes/py
C=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance
SDK=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-python
cd /home/zhijie/Desktop/github/be-assembly-standard && source $S/accenv.sh
OUT=$S/prof/variants2; rm -rf "${OUT:?}"; mkdir -p $OUT; cd $OUT
measure() { for surface in http grpc; do KEEP_VENV=1 timeout 300 uv run --project $C python $S/prof/cpu_per_request.py $OUT "$1" $surface 100 20 2>&1 | grep '^{' >> $OUT/results.jsonl || echo "{\"label\": \"$1\", \"surface\": \"$surface\", \"failed\": true}" >> $OUT/results.jsonl; done; }
probe_sdk() { (cd $SDK && git checkout -q "$1") && VIRTUAL_ENV=$P/.venv uv pip install -q --python $P/.venv/bin/python --reinstall-package be-sdk "$SDK"; }
probe_pkg() { VIRTUAL_ENV=$P/.venv uv pip "$1" -q --python $P/.venv/bin/python uvloop; }
sdk_tests() {  # <branch> <label> [plugin]
  (cd $SDK && git checkout -q "$1" && source $S/itenv.sh && if [ -n "${3:-}" ]; then VIRTUAL_ENV= uv pip install -q --python $SDK/.venv/bin/python uvloop; PYTHONPATH=$S/prof/plugin timeout 900 uv run pytest -q -m integration -p uvloop_policy > $OUT/sdk-$2.log 2>&1; uv pip uninstall -q --python $SDK/.venv/bin/python uvloop; else timeout 900 uv run pytest -q -m integration > $OUT/sdk-$2.log 2>&1; fi; echo "{\"sdk_integration\": \"$2\", \"result\": \"$(tail -1 $OUT/sdk-$2.log)\"}" >> $OUT/results.jsonl)
}
(cd $P && uv sync --frozen --no-dev -q)
measure a7
probe_sdk perf/uvloop; measure uvloop-off
probe_pkg install; measure uvloop
probe_pkg uninstall; probe_sdk perf/aiohttp; measure aiohttp
probe_sdk perf/both; probe_pkg install; measure both
sdk_tests perf/aiohttp aiohttp
sdk_tests perf/both both-uvloop plugin
(cd $SDK && git checkout -q main)
(cd $P && uv sync --frozen --no-dev -q)
echo DONE >> $OUT/results.jsonl
