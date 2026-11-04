#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (T4g, part 1): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4g part 1, closure and index), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
C=authz/closure.go
mut $C '		if b.RoleRevision != "" && !w.roles[b.RoleRevision] {' '		if false {' "a grant whose role revision ended is not closed"
mut $C '	case lim == nil:
		return booked{state: "ended", endReason: "source_ended"}' '	case lim == nil:
		return booked{}' "a record whose unit ended is not closed"
mut $C '	case len(lim.cut(segs, grantee)) == 0:' '	case false:' "a record with nothing left is not closed"
mut $C '	return booked{review: !lim.covers(segs, grantee)}' '	return booked{review: false}' "partly outside is not marked for review"
mut $C '		if w.limits.of(b.Unit) == nil {' '		if false {' "a holding whose unit ended is not closed"
mut $C '		return m.closeAfter(ctx, tx, t.Type, id) // its effective limit moved with its parent' '		return nil // its effective limit moved with its parent' "a unit's closure does not go on to its own dependents"
mut $C '	if complete {' '	if true {' "an index that is not complete is trusted"
mut $C '			if id != a.Ref && sameUnit(w.units, id, a.Ref) {' '			if false {' "a unit's closure misses what names its superseded records"
mut authz/enact.go '	if t := p.target; t != nil && !p.activate && (t.Type == "management_unit" || t.Type == "role_revision") {' '	if t := p.target; false && t != nil && !p.activate && (t.Type == "management_unit" || t.Type == "role_revision") {' "a source that tightens registers no closure"
mut authz/enact.go '	return id, indexSources(ctx, tx, id, p.recType, body)' '	return id, nil' "a new record is not indexed"
mut authz/view.go '		if b.RoleRevision != "" && !activeRole[b.RoleRevision] {' '		if false && activeRole[""] {' "the view gives a grant whose role revision ended"
mut authz/effect.go '				out[pred] = u' '				_ = u' "a superseded unit does not resolve to its successor"
mut authz/facts.go '		if slices.ContainsFunc(s.held, func(h string) bool { return sameUnit(s.units, h, u) }) {' '		if slices.Contains(s.held, u) {' "a holding of a superseded unit is not one of its successor"
echo "done" >> "$out"
