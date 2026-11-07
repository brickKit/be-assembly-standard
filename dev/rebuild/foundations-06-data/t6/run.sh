#!/usr/bin/env bash
# T6 of foundations item 6: the Python long simulation, 30 minutes of crashes (tests/sim/test_simulation.py).
echo $$ > "$(dirname "$0")/sim.pid"
O="$(dirname "$(realpath "$0")")"
cd /home/zhijie/Desktop/github/be-assembly-standard
set -a; . dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1; set +a
cd tools/be-sdk-python
echo "power=$(powerprofilesctl get) start=$(date -Is) sdk=$(git describe --tags --always)" > "$O/sim.log"
SIM_MINUTES=30 PYTHONDONTWRITEBYTECODE=1 uv run pytest -q -p no:cacheprovider -s -m simulation tests/sim >> "$O/sim.log" 2>&1
echo "SIM-T6 ALL-DONE rc=$? end=$(date -Is)" >> "$O/sim.log"
