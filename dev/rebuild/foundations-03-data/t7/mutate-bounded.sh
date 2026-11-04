#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.21 (T7a: subject-relative atoms and budgets): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.21 in progress (T7a), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
F=authz/facts.go; S=authz/security.go; E=authz/effective.go; B=authz/budget.go; D=authz/disposition.go; X=authz/enact.go
mut $F '		why, err := m.contains(ctx, tx, segs, lim, grantee)' '		why, err := m.contains(ctx, tx, segs, lim, "")' "a grant's containment without its grantee"
mut $S '	if c.Kind == "self" && l.Kind == "self" {
		return ""
	}' '' "self within self not contained"
mut $S '	if a.Kind == "self" && grantee != "" {' '	if false && a.Kind == "self" && grantee != "" {' "self not instantiated"
mut $S '		return "unprovable (self with no grantee to stand for)"' '		return ""' "self with no grantee contained"
mut $E '		out = &limit{segs: parent.cut(u.ManagedScope, grantee), ops: u.GrantableOperations}' '		out = &limit{segs: parent.cut(u.ManagedScope, ""), ops: u.GrantableOperations}' "a unit's limit walked without the grantee"
mut $E '	key := unit + "\x00" + grantee' '	key := unit' "limits memoized across grantees"
mut $B '	if len(segs) > budgetGrantSegments {' '	if false && len(segs) > budgetGrantSegments {' "no segments-per-grant budget"
mut $B '			case a.Kind == "in" && len(a.Values) > budgetInValues:' '			case false && a.Kind == "in" && len(a.Values) > budgetInValues:' "no values budget"
mut $B '			case a.Kind == "tree" && len(a.Items) > budgetTreeItems:' '			case false && a.Kind == "tree" && len(a.Items) > budgetTreeItems:' "no tree items budget"
mut $B '		if n := len(scopes[op]); n > budgetSubjectSegments {' '		if n := len(scopes[op]); n > budgetSubjectSegments+1000 {' "no per-subject budget"
mut $B "state IN ('active', 'scheduled')" "state IN ('active')" "scheduled grants not counted"
mut $B '		}{s.Atoms, s.Valid, s.Binding})' '		}{s.Atoms, sdkauthz.Window{}, s.Binding})' "validity ignored when merging scopes"
mut $F '		if err := m.budgetOf(ctx, tx, b, f, p, c.Predecessor); err != nil {' '		if err := m.budgetOf(ctx, tx, b, f, p); err != nil {' "a renewal counts its predecessor"
mut $F '	if b, ok := p.body.(grantBody); ok { // the budgets (security 07): row 19; the predecessor' '	if b, ok := p.body.(grantBody); ok && false { // the budgets (security 07): row 19; the predecessor' "no budget on a submitted grant"
mut $F '	if b, ok := p.body.(grantBody); ok { // the budgets again, now (row 19)' '	if b, ok := p.body.(grantBody); ok && false { // the budgets again, now (row 19)' "no budget on a saved grant coming due"
mut $F '		if err := m.budgetOf(ctx, tx, b, f, p, t.ID); err != nil { // over a budget now: kept held (row 26)' '		if err := error(nil); err != nil { // over a budget now: kept held (row 26)' "no budget on a restore"
mut $D 'm.contains(ctx, tx, in.SuspendedSegments, s.limits.ofFor(domain, in.Subject), in.Subject)' 'm.contains(ctx, tx, in.SuspendedSegments, s.limits.of(domain), "")' "a disposition's scope without the disposed person"
mut authz/change.go '	case row == 18 && p.whyNot != "":' '	case false:' "no dimension in a containment rejection"
echo "done" >> "$out"
