#!/bin/bash
# Twice under the performance power profile; records and restores the profile.
before=$(powerprofilesctl get)
trap 'powerprofilesctl set "$before"; echo "POWER restored $(powerprofilesctl get)"' EXIT
powerprofilesctl set performance; echo "POWER $before -> $(powerprofilesctl get) $(date -Is)"
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-python
for i in 1 2; do echo "== run $i"; uv run --with jsonschema-rs==0.59.0 python -I /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/sdkjs/bench.py; done
echo "END $(date -Is)"
