#!/bin/bash
# The write latency in the performance power profile with every CPU kept out of deep sleep (keepawake.py): the
# probes 3.2.4 and 3.2.7, write at 50/s for 30 s, two rounds interleaved.
set -u
S=<scratch>
OUT=$S/cstate-perf; CONF=<repo>/tools/be-acceptance/conformance
source $S/accenv.sh
mkdir -p $OUT; echo $$ > $OUT/pid
setsid python3 $S/keepawake.py > $OUT/keepawake.pids 2>&1 &
KA=$!
sleep 1
for r in 1 2; do
  for v in 3.2.4 3.2.7; do
    W=$S/bisect/cells/D-bisect-${v//./}; L=$OUT/run-$r-$v.log
    echo "RUN $r $v BEGIN $(date -Is)" >> $OUT/status.log
    ( cd $CONF && uv run python -m cells prepare $W && cd $W && brickkit up && cd $CONF &&
      uv run python -m cells run $W $OUT/measure/r$r/$v --ops write --loads 50 --idle 5 --warmup 5 --seconds 30 ) > $L 2>&1
    rc=$?
    (cd $W && brickkit down) >> $L 2>&1
    echo "RUN $r $v END exit=$rc $(date -Is)" >> $OUT/status.log
  done
done
kill -TERM -- -$KA 2>/dev/null; kill $(cat $OUT/keepawake.pids) $KA 2>/dev/null
echo "END $(date -Is)" >> $OUT/status.log
