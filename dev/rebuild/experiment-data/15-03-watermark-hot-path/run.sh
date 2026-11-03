#!/usr/bin/env bash
# The watermark consumer's hot paths (be-sdk-go projection benchmarks, integration tag), three runs of 200 operations
# each, in performance power mode (restored on exit). Run from be-sdk-go with BE_SDK_TEST_PG_ADMIN set.
set -euo pipefail
out=$1
mode=$(powerprofilesctl get); trap 'powerprofilesctl set "$mode"' EXIT; powerprofilesctl set performance
{ echo "# $(date -Is) power mode: $(powerprofilesctl get) (was $mode); be-sdk-go $(git rev-parse --short HEAD); load: $(cut -d' ' -f1-3 /proc/loadavg)"
  go test -count=3 -tags integration -run '^$' -bench 'Benchmark' -benchtime 200x ./projection/
  echo "# $(date -Is) done"; } > "$out" 2>&1
