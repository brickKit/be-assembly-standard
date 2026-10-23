#!/usr/bin/env bash
# One cell end to end: create, prepare, build, up, secure, seed-data (twice: the second must change nothing), L3 scenarios,
# profile (stops the cell). Markers per phase: <PHASE>-OK / <PHASE>-FAILED, then DONE.
# Usage: cell-full.sh <CELL> <log> [first phase: create|seed1|settle|seed2|scenarios|profile]
set -u -o pipefail
CELL=$1; LOG=$2; FROM=${3:-create}
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad
ROOT=/home/zhijie/Desktop/github/be-assembly-standard
CDIR=$ROOT/dev/rebuild/experiment-cells/$CELL
CONF=$ROOT/tools/be-acceptance/conformance
. $S/cellenv.sh
export SEED_PASSWORD=$BE_ACC_IAM_TEST_PASSWORD
if [ "$FROM" = create ]; then : > $LOG; else sed -i '/^DONE$/d' $LOG; fi
step() {  # step <PHASE> <command...>: output to $LOG.<phase>
  local phase=$1; shift
  echo "$phase-START $(date +%T)" >> $LOG
  if "$@" >> "$LOG.$phase" 2>&1; then echo "$phase-OK $(date +%T)" >> $LOG; return 0; fi
  echo "$phase-FAILED $(date +%T) (see $LOG.$phase)" >> $LOG; echo DONE >> $LOG; exit 1
}
# settle: the background work a seed leaves (the second half of cancellations and completions) has finished when two
# snapshots 15 s apart are the same; then the snapshot the rerun is compared with
settle() {
  local a=$LOG.settle.a b=$LOG.settle.b
  $S/vsum.sh > $a
  for _ in $(seq 1 20); do sleep 15; $S/vsum.sh > $b; cmp -s $a $b && { cp $b $LOG.vsum1; return 0; }; mv $b $a; done
  echo "still changing after 5 min"; diff $a $b; return 1
}
after() {  # after <phase>: true when <phase> is FROM or comes after it
  local order="create seed1 settle seed2 scenarios profile" seen=0
  for p in $order; do [ "$p" = "$FROM" ] && seen=1; [ "$p" = "$1" ] && return $((1-seen)); done; return 1; }
if after create; then
  (cd $CDIR && brickkit down >/dev/null 2>&1 || true)
  step create bash -c "cd $CONF && uv run python -m cells create $CDIR && uv run python -m cells prepare $CDIR"
  step build bash -c "cd $CDIR && brickkit build"
  step up bash -c "cd $CDIR && brickkit up"
  step secure bash -c "cd $CONF && timeout 900 uv run python -m cells secure $CDIR"
fi
after seed1 && step seed1 make -C $ROOT seed-data
after settle && step settle settle
if after seed2; then
  step seed2 make -C $ROOT seed-data
  sleep 15; $S/vsum.sh > $LOG.vsum2
  step rerun diff $LOG.vsum1 $LOG.vsum2
fi
after scenarios && step scenarios bash -c "cd $CONF && BE_ACC_CELL=$CDIR timeout 600 uv run pytest -v scenarios"
after profile && step profile bash -c "cd $CONF && uv run python -m cells profile $CDIR"
echo DONE >> $LOG
