#!/usr/bin/env bash
# Round 2 of the T4f mutations, appended to round 1's output: each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1
echo "round 2, $(date -I): the survivors against the two new cases, the four that did not compile rewritten; a crash (FAIL without --- FAIL) counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
E=authz/effective.go
mut $E '		closed := isClosed(aClosed) && isClosed(bClosed)' '		closed := isClosed(aClosed) || isClosed(bClosed)' "touching ends: an open end closes"
mut $E '		if !slices.Contains(l.ops, s.Operation) {
			continue' '		if false {
			continue' "an operation the unit may not grant gives segments"
mut $E '	if !ok || depth > len(l.units) {' '	if !ok {' "a cycle of units has no end (no depth guard)"
mut $E '	return ok && (cmp < 0 || cmp == 0 && isClosed(a.LoClosed) && isClosed(a.HiClosed))' '	return ok && (cmp < 0 || cmp >= 0)' "an empty interval is not empty"
mut $E '	if bf.After(af) {' '	if bf.After(af) && false {' "the validity keeps the earlier start"
mut $E '		if !u.After(f) {' '		if !u.After(f) && false {' "validities that do not overlap meet"
mut authz/view.go '		for _, s := range lims.of(b.GovernanceUnit).cut(b.Segments, b.Grantee) {' '		for _, s := range append(lims.of(b.GovernanceUnit).cut(nil, ""), b.Segments...) {' "the view gives the grant's own segments"
echo "done round 2" >> "$out"
