#!/bin/bash
# Which release raised the Go write request's latency: cells with only test/probe-go and -go2 alone, at the probes
# 3.2.4 (SDK alpha.7), 3.2.5 (alpha.8: wake by partition, Go 1.27), 3.2.7 (alpha.10); the write operation at 50/s for
# 30 s, three rounds interleaved so machine drift spreads over all versions.
set -u
OUT=$1; S=<scratch>
CONF=<repo>/tools/be-acceptance/conformance
source $S/accenv.sh
mkdir -p $OUT; echo $$ > $OUT/pid
for v in 3.2.4 3.2.5 3.2.7; do
  W=$OUT/cells/D-bisect-${v//./}; mkdir -p $W
  printf 'cell: D-bisect-%s\nalone: [test/probe-go@%s, test/probe-go2@%s]\nchain: [test/probe-go, test/probe-go2]\n' "${v//./}" "$v" "$v" > $W/cell.yaml
  (cd $CONF && uv run python -m cells create $W) > $OUT/create-$v.log 2>&1 || { echo "CREATE FAILED $v" >> $OUT/status.log; exit 1; }
done
for r in 1 2 3; do
  for v in 3.2.4 3.2.5 3.2.7; do
    W=$OUT/cells/D-bisect-${v//./}; L=$OUT/run-$r-$v.log
    echo "RUN $r $v BEGIN $(date -Is)" >> $OUT/status.log
    ( cd $CONF && uv run python -m cells prepare $W && cd $W && brickkit build && brickkit up && cd $CONF &&
      uv run python -m cells run $W $OUT/measure/r$r/$v --ops write --loads 50 --idle 5 --warmup 5 --seconds 30 ) > $L 2>&1
    rc=$?
    (cd $W && brickkit down) >> $L 2>&1
    echo "RUN $r $v END exit=$rc $(date -Is)" >> $OUT/status.log
  done
done
echo "END $(date -Is)" >> $OUT/status.log
