#!/bin/bash
# K1 mutation check of the authz replay (T9c): each mutant must turn TestTheReplayAppliesTheEvidenceAgain red.
set -u
cd /home/zhijie/Desktop/github/be-assembly-standard/components/infra/authz
. /tmp/claude-1000/mt/allenv.sh
out=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/foundations-04-data/t9/authz-mutants
mut() { # name file old new
  local name=$1 f=$2 old=$3 new=$4
  cp "$f" "$f.orig"
  python3 - "$f" "$old" "$new" <<'PY' || { mv "$f.orig" "$f"; echo "$name: NOT APPLIED"; return; }
import sys
p,o,n=sys.argv[1:]
s=open(p).read()
assert s.count(o)==1, "pattern count %d" % s.count(o)
open(p,'w').write(s.replace(o,n))
PY
  timeout 280 go test -tags integration -count=1 -run TestTheReplayAppliesTheEvidenceAgain ./authz/ >"$out/$name.log" 2>&1
  local rc=$?
  mv "$f.orig" "$f"
  if [ $rc -eq 0 ]; then echo "$name: SURVIVED"; else echo "$name: killed ($(grep -v '^        {' "$out/$name.log" | grep -m1 -E 'Error:|Messages:|undefined|cannot' | sed 's/^ *//'))"; fi
}
mut m1-no-replay-facts authz/change.go '			f = replayFacts(f)' '			_ = replayFacts(f)'
mut m2-new-identity authz/enact.go '		id = e.replay' '		_ = e.replay'
mut m3-no-digest authz/replay.go '		req.CandidateDigest = candidateDigest(c.RecordType, raw)' '		_ = candidateDigest(c.RecordType, raw)'
mut m4-ended-not-accepted authz/replay.go 'if state == "ended" { //' 'if state == "never" { //'
mut m5-general-on-replay authz/change.go '		e.replay == "" {
		// a widening' '		true {
		// a widening'
mut m6-no-dangling authz/replay.go '			return fmt.Errorf("record %s: %w", req.Target, evidence.ErrDangling)' '			return fmt.Errorf("record %s: gone", req.Target)'
echo "MUTANTS DONE"
