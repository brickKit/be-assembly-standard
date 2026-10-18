#!/bin/bash
# The write latency in the performance power profile: the probes 3.2.4 and 3.2.7 alone (the bisection cells), write
# at 50/s for 30 s, three rounds interleaved.
set -u
OUT=$1; S=<scratch>
CONF=<repo>/tools/be-acceptance/conformance
source $S/accenv.sh
mkdir -p $OUT; echo $$ > $OUT/pid
for v in 3.2.4 3.2.7; do
  W=$S/bisect/cells/D-bisect-${v//./}; mkdir -p $W
done
for r in 1 2 3; do
  for v in 3.2.4 3.2.7; do
    W=$S/bisect/cells/D-bisect-${v//./}; L=$OUT/run-$r-$v.log
    echo "RUN $r $v BEGIN $(date -Is)" >> $OUT/status.log
    ( cd $CONF && uv run python -m cells prepare $W && cd $W && brickkit build && brickkit up && cd $CONF &&
      uv run python -m cells run $W $OUT/measure/r$r/$v --ops write --loads 50 --idle 5 --warmup 5 --seconds 30 ) > $L 2>&1
    rc=$?
    (cd $W && brickkit down) >> $L 2>&1
    echo "RUN $r $v END exit=$rc $(date -Is)" >> $OUT/status.log
  done
done
echo "END $(date -Is)" >> $OUT/status.log
