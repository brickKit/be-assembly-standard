#!/usr/bin/env bash
# Mutation runs for infra/authz's tightening-only operations (T5e: the tightening route, T_tight on the last applied
# facts, confirmers by the last applied facts, objects that touch an admin's availability, the basis in the result
# and the audit): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.18 in progress (T5e), second round after the tests that cover the first round's survivors, $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
R=authz/requester.go; C=authz/confirm.go; F=authz/facts.go
mut $R '	a.last = l == proven' '	a.last = l == proven && false' "no last applied facts: every stale tightening refused"
mut $F '	if p.confirmed, err = m.confirmationsOf(ctx, tx, req.ConfirmationIDs, t, requester, holderOf, !f.AffectsAdmins, f); err != nil {' '	if p.confirmed, err = m.confirmationsOf(ctx, tx, req.ConfirmationIDs, t, requester, holderOf, true, f); err != nil {' "a confirmer of an admin's holding by the last applied facts"
mut $C '			if state == "awaiting_confirmation" {
				op = OpChange
			}' '' "a saved widening is confirmed with the tightening operation"
echo "done" >> "$out"
