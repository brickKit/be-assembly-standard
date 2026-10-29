#!/bin/bash
# Builds the three variants of the Python probe from the same source (be-acceptance probes/py) as pyvar-<variant>:1,
# one image for both test/probe-py and test/probe-py2 (no PORT in the image: BrickKit gives each its manifest's port),
# and prints each one's interpreter build (version and configure flags).
# Record 10-04 ran on the probe at 3.2.19 (D9-probe-pyonly pins it, run.sh tags test-probe-py:3.2.19): to repeat it,
# check probes/py out at the tag test-probe-py/3.2.19 first (3.2.20 refuses to start as 3.2.19).
# Usage: build.sh [variant...]   (default: alpine slim pbs)
set -eu
H=$(cd "$(dirname "$0")" && pwd); SRC=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/probes/py
for v in "${@:-alpine slim pbs}"; do for x in $v; do
  docker build -q -f "$H/Dockerfile.$x" -t "pyvar-$x:1" "$SRC" >/dev/null
  echo "pyvar-$x: $(docker run --rm --entrypoint python "pyvar-$x:1" -c 'import sys,sysconfig; c=sysconfig.get_config_var("CONFIG_ARGS"); print(sys.version.split()[0], sys.version.split("[")[-1].rstrip("]"), "PGO" if "--enable-optimizations" in c else "no-PGO", "BOLT" if "bolt" in c else "", "mimalloc" if "mimalloc" in c else "", "tail-call" if "tail-call" in c else "")') $(docker image inspect -f '{{.Size}}' "pyvar-$x:1" | awk '{printf "%.0f MB", $1/1e6}')"
done; done
