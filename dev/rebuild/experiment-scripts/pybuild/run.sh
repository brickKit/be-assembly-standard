#!/bin/bash
# The Python builds compared on the same hop (step10-plan.md 5.5): the cell D9-probe-pyonly (two Python probes calling
# each other) runs once per pass of each variant, in the order ORDER (default alpine slim pbs pbs slim alpine: each
# twice, mirrored, so a drift through the batch shows), through probe9.sh (idle IDLE seconds, then four operations at
# 200/s). Before each pass test-probe-py:3.2.19 and test-probe-py2:3.2.19 are tagged to pyvar-<variant>:1 and pyvar-<variant>-py2:1 (build.sh);
# the original images are kept as :3.2.19-orig and tagged back at the end, whatever happens.
# Usage: run.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
ORDER=${ORDER:-alpine slim pbs pbs slim alpine}
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
log() { echo "NIGHT $* $(date -Is)" >> "$OUT/night.log"; }
for p in test-probe-py test-probe-py2; do
  docker image inspect "$p:3.2.19-orig" >/dev/null 2>&1 || docker tag "$p:3.2.19" "$p:3.2.19-orig"
done
restore() { for p in test-probe-py test-probe-py2; do docker tag "$p:3.2.19-orig" "$p:3.2.19"; done; log restored; }
trap restore EXIT
log START order="$ORDER"
n=0
for v in $ORDER; do
  n=$((n + 1))
  docker tag "pyvar-$v:1" test-probe-py:3.2.19; docker tag "pyvar-$v-py2:1" test-probe-py2:3.2.19
  log "PASS $n $v"
  IDLE=${IDLE:-120} OPS=${OPS:-echo-1k-grpc,echo-1k-http,write,relay} LOADS=${LOADS:-200} \
    "$X/probe9.sh" "$OUT/$n-$v" D9-probe-pyonly
  log "PASS $n $v done exit=$?"
done
restore; trap - EXIT
log ALL-DONE
