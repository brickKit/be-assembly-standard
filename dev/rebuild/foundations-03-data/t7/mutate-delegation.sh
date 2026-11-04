#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.21 (T7b: re-delegation and management actions, A131): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.21 in progress (T7b), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
F=authz/facts.go; T=authz/target.go; G=authz/delegate.go; C=authz/claim.go
mut $F '		structural, f.ManagementWiden, p.body, segs = s.managesWith(b.Parent, ActDelegate), true, b, b.ManagedScope' '		structural, f.ManagementWiden, p.body, segs = s.manages(b.Parent), true, b, b.ManagedScope' "a child unit without delegate_management"
mut $F '		if why := delegation(s.units, b, m.maxDepth); why != "" {' '		if why := ""; why != "" {' "no re-delegation containment"
mut $F '		if why := unitShape(b); why != "" {
			return false, why, nil, nil
		}' '' "a unit candidate's shape unchecked"
mut $F '		structural = s.managesWith(b.Unit, ActDelegate) && (b.SystemRole == "" || s.admin)' '		structural = s.manages(b.Unit) && (b.SystemRole == "" || s.admin)' "a holding without delegate_management"
mut $F '			action = ActBindRole' '			action = ActGrant' "a role binding takes grant"
mut $F '		structural, p.body, segs, grantee = s.managesWith(b.GovernanceUnit, action), b, b.Segments, b.Grantee' '		structural, p.body, segs, grantee = s.manages(b.GovernanceUnit) || action == "", b, b.Segments, b.Grantee' "a grant without its action"
mut $F '		if u, ok := p.body.(unitBody); ok && underItself(s.units, u.Parent, c.Predecessor) {' '		if u, ok := p.body.(unitBody); ok && false && underItself(s.units, u.Parent, c.Predecessor) {' "a unit renewed under itself"
mut $F '			structural, p.endReason = veto || s.managesWith(unitOf, actionFor(t.Type)), "cancelled"' '			structural, p.endReason = veto || s.manages(unitOf), "cancelled"' "a cancellation without its action"
mut $F '		manages := s.managesWith(unitOf, actionFor(t.Type)) // revoke for a grant, delegate_management otherwise (A131)' '		manages := s.manages(unitOf) // revoke for a grant, delegate_management otherwise (A131)' "a tightening without its action"
mut $G '		return ActRevoke' '		return ActDelegate' "a grant's tightening takes delegate_management"
mut $G '		out = common(out, b.ManagementActions)' '		_ = b' "a unit's actions not narrowed by those above"
mut $G '		if eff--; depths[i] < eff {' '		if depths[i] < eff {' "a unit's depth not less than its parent's"
mut $G '	if level := levelOf(units, b.Parent) + 1; level > maxLevel {' '	if level := levelOf(units, b.Parent) + 1; level > maxLevel+100 {' "no deployment maximum"
mut $G '			slices.Contains(actionsOf(s.units, u), action) {' '			true {' "holding any unit gives every action"
mut $T '			!coversAll(cur.ManagedScope, next.ManagedScope) || unitShape(next) != "" ||' '			!coversAll(cur.ManagedScope, next.ManagedScope) ||' "a narrowing's shape unchecked"
mut $T '			cur.MaxSubdelegationDepth != nil && *next.MaxSubdelegationDepth > *cur.MaxSubdelegationDepth {' '			false && cur.MaxSubdelegationDepth != nil && *next.MaxSubdelegationDepth > *cur.MaxSubdelegationDepth {' "a narrowing deepens"
mut $T '			if !slices.Contains(cur.ManagementActions, a) {
				return nil, false
			}' '' "a narrowing adds an action"
mut $C '		{root, "management_unit", unitBody{Name: "deployment", Root: true, ManagementActions: allActions,' '		{root, "management_unit", unitBody{Name: "deployment", Root: true, ManagementActions: allActions[:1],' "the root grants only"
echo "done" >> "$out"
