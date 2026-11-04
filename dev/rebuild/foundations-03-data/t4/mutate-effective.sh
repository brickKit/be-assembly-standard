#!/usr/bin/env bash
# Mutation runs for infra/authz's effective segments (T4f): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4f, effective segments), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
E=authz/effective.go
mut $E '		v := common(x.Values, y.Values)' '		v := x.Values' "value sets are not intersected"
mut $E '		return x, grantee != "" && slices.Contains(y.Values, grantee)' '		return x, true' "self is within any set"
mut $E '				case covers(b, a):
					items = append(items, a)' '				case covers(b, a):
					items = append(items, b)' "a subtree within another keeps the wider"
mut $E '	case cmp*side < 0: // a is inside b' '	case cmp*side > 0: // a is inside b' "an interval keeps the looser end"
mut $E '	return ok && (cmp < 0 || cmp == 0 && isClosed(a.LoClosed) && isClosed(a.HiClosed))' '	return ok' "an empty interval is not empty"
mut $E '		closed := isClosed(aClosed) && isClosed(bClosed)' '		closed := isClosed(aClosed) || isClosed(bClosed)' "touching ends: an open end closes"
mut $E '		if x.Currency != y.Currency {
			return sdkauthz.Atom{}, false' '		if false {
			return sdkauthz.Atom{}, false' "intervals in two currencies meet"
mut $E '	return sdkauthz.Atom{}, false
}

// tighterBound' '	return x, true
}

// tighterBound' "a pair outside the table keeps the first atom"
mut $E '	if bf.After(af) {
		out.From = b.From' '	if false {
		out.From = b.From' "the validity keeps the earlier start"
mut $E '		if !u.After(f) {' '		if false {' "validities that do not overlap meet"
mut $E '			out.ops = common(u.GrantableOperations, parent.ops)' '			out.ops = u.GrantableOperations' "a unit may grant what its parent may not"
mut $E '		if !slices.Contains(l.ops, s.Operation) {
			continue' '		if false {
			continue' "an operation the unit may not grant gives segments"
mut $E '	if !ok || depth > len(l.units) {' '	if !ok {' "a cycle of units has no end (no depth guard)"
mut $E '	out.ReadFields = common(a.ReadFields, b.ReadFields)' '	out.ReadFields = a.ReadFields' "the fields are not intersected"
mut authz/view.go '		for _, s := range lims.of(b.GovernanceUnit).cut(b.Segments, b.Grantee) {' '		for _, s := range b.Segments {' "the view gives the grant's own segments"
mut authz/view.go '	return mine && d.operations[s.Operation] && reg.usable(s.Operation)' '	return mine && d.operations[s.Operation]' "a retired key takes part"
mut authz/view.go '	return mine && d.operations[s.Operation] && reg.usable(s.Operation)' '	return mine && reg.usable(s.Operation)' "a key its owner no longer defines takes part"
mut authz/facts.go '		structural, p.body, lim, segs = s.manages(b.GovernanceUnit), b, s.limits.of(b.GovernanceUnit), b.Segments' '		structural, p.body, lim, segs = s.manages(b.GovernanceUnit), b, &limit{segs: s.units[b.GovernanceUnit].ManagedScope, ops: s.units[b.GovernanceUnit].GrantableOperations, all: s.units[b.GovernanceUnit].Root}, b.Segments' "the effect point proves against the unit's own scope"
echo "done" >> "$out"
