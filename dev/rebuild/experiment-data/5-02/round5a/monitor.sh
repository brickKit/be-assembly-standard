#!/bin/bash
# The campaign's watcher (cells/watch.py: failures, stalls, implausible measurements, a summary every 5 minutes, the
# end) plus a check every 30 s that the power profile stays performance while the campaign runs.
O=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/round5a
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance
uv run python cells/watch.py $O/measure /home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-cells/campaign-round5a.yaml $1 &
W=$!
warned=""
while kill -0 $W 2>/dev/null; do
  sleep 30
  if grep -q "POWER .* -> performance" $O/status.log 2>/dev/null && ! grep -q "^END" $O/status.log; then
    m=$(powerprofilesctl get)
    if [ "$m" != performance ] && [ "$warned" != "$m" ]; then echo "PROBLEM: the power profile is $m during the measurement"; warned=$m; fi
  fi
  if grep -q "^END" $O/status.log 2>/dev/null; then sleep 40; kill $W 2>/dev/null; echo "RUN END: $(grep '^END' $O/status.log) $(grep 'POWER restored' $O/status.log)"; exit 0; fi
done
