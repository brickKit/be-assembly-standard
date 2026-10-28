#!/bin/bash
# Builds the three variants of the Python probe from the same source (be-acceptance probes/py) as pyvar-<variant>:1
# (port 8601, for test/probe-py) and pyvar-<variant>-py2:1 (port 8605, for test/probe-py2),
# and prints each one's interpreter build (version and configure flags).
# Usage: build.sh [variant...]   (default: alpine slim pbs)
set -eu
H=$(cd "$(dirname "$0")" && pwd); SRC=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/probes/py
for v in "${@:-alpine slim pbs}"; do for x in $v; do
  docker build -q -f "$H/Dockerfile.$x" -t "pyvar-$x:1" "$SRC" >/dev/null                         # PORT 8601 (probe-py)
  docker build -q -f "$H/Dockerfile.$x" --build-arg PORT=8605 -t "pyvar-$x-py2:1" "$SRC" >/dev/null  # probe-py2
  echo "pyvar-$x: $(docker run --rm --entrypoint python "pyvar-$x:1" -c 'import sys,sysconfig; c=sysconfig.get_config_var("CONFIG_ARGS"); print(sys.version.split()[0], sys.version.split("[")[-1].rstrip("]"), "PGO" if "--enable-optimizations" in c else "no-PGO", "BOLT" if "bolt" in c else "", "mimalloc" if "mimalloc" in c else "", "tail-call" if "tail-call" in c else "")') $(docker image inspect -f '{{.Size}}' "pyvar-$x:1" | awk '{printf "%.0f MB", $1/1e6}')"
done; done
