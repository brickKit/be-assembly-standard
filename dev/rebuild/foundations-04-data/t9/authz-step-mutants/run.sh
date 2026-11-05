#!/bin/bash
# K1 mutation check of the authorization member's 6.4-6.5 (infra/authz 3.0.30, T9c): each mutant must turn
# TestTheRecoveryStepAfterTheReplay red.
set -u
cd /home/zhijie/Desktop/github/be-assembly-standard/components/infra/authz
. /tmp/claude-1000/mt/allenv.sh
out=$(dirname "$(readlink -f "$0")")
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
  timeout 250 go test -tags integration -count=1 -run TestTheRecoveryStepAfterTheReplay ./authz/ >"$out/$name.log" 2>&1
  local rc=$?
  mv "$f.orig" "$f"
  if [ $rc -eq 0 ]; then echo "$name: SURVIVED"; else echo "$name: killed ($(grep -v '^        {' "$out/$name.log" | grep -m1 -E 'Messages:|Error:|undefined' | sed 's/^ *//'))"; fi
}
R=authz/recoverystep.go
mut m01-any-caller authz/module.go '	tool := []string{RecoveryTool}' '	tool := []string{grpcx.AnyComponent}'
mut m02-always-applied $R '		src.Applied, err = m.accounts.NoOlderThan(ctx, tx, asOf)' '		_, err = m.accounts.NoOlderThan(ctx, tx, asOf)
		src.Applied = true'
mut m03-since-ignored $R '			return nil, errs.New(errs.ReasonRequestInvalid, "since is the as_of of a first answer")' '			t = time.Now()'
mut m04-no-account-ends $R '		w.ended = ended' '		_ = ended'
mut m05-admins-closed $R '			if len(admin) > 0 { // an authorization admin stays open' '			if len(admin) > 99 { // an authorization admin stays open'
mut m06-closed-twice $R '		AND state = '"'"'active'"'"')`, subject, originRecoveryReview).Scan(&open); err != nil || open {' '		AND state = '"'"'active'"'"')`, subject, originRecoveryReview).Scan(&open); err != nil || (open && false) {'
mut m07-no-judge $R '		if err := m.judgeAdmins(ctx, tx); err != nil {' '		if err := error(nil); err != nil {'
mut m08-last-admin-executed $R '			if after == disproven {' '			if after == 99 {'
mut m09-no-closing $R '				if _, err := m.closeForReview(ctx, tx, h, in.GetRecovery(), r.ID); err != nil {' '				if _, err := h, error(nil); err != nil {'
mut m10-any-phase $R '	if r.Category != "security_tightening" || r.Phase != "intent" {' '	if r.Category != "security_tightening" {'
mut m11-dangling-error $R '		out.Outcome, out.Detail, err = evidence.Dangling, err.Error(), nil // rolled back: nothing written' '		out.Outcome, out.Detail = evidence.Dangling, err.Error()'
mut m12-recovery-keeps-review authz/recovery.go "		AND (d.origin IN ('identity_side', 'recovery_review') OR d.disposer IN" "		AND (d.origin IN ('identity_side') OR d.disposer IN"
echo "MUTANTS DONE"
