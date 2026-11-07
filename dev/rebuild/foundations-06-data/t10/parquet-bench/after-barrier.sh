#!/usr/bin/env bash
# Waits for the night barrier measurement to finish (its outermost done mark) and the machine to be quiet, then runs
# the Parquet rounds. Gives up after 4 hours.
for i in $(seq 1 480); do
  if grep -qE "BARRIER (ALL-DONE|FAILED)" "/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/foundations-05-data/t12-barrier/night/status.log" 2>/dev/null && ! systemctl --user is-active --quiet be-barrier-night.service \
     && [ "$(cut -d' ' -f1 /proc/loadavg | cut -d. -f1)" -lt 2 ]; then
    echo "PQWAIT start $(date -Is)"
    PY=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/pq-probe/.venv/bin/python exec "/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/foundations-06-data/t10/parquet-bench/run.sh" "/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/foundations-06-data/t10/parquet-bench/run1"
  fi
  sleep 30
done
echo "PQWAIT gave up $(date -Is)"
