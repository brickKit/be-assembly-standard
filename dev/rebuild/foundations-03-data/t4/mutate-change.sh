#!/usr/bin/env bash
# Mutation runs for infra/authz's new effect point (T4a-T4c): each rule broken by one edit, TestMemberEndToEnd run,
# the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4a-T4c), $(date -I): each rule broken by one edit, TestMemberEndToEnd run, the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q "^--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "Error:|Messages:" -A1 | grep -v '^--$\|"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/change.go '			if _, err := m.transition(ctx, tx, p.successor, "ended", "superseded", "", requester+":"+req.ChangeKey); err != nil {' '			if _, err := m.transition(ctx, tx, p.successor, "active", "", "", requester+":"+req.ChangeKey); err != nil {' "a superseding record leaves its predecessor active"
mut authz/change.go 'f.Contained = f.Contained && coversAll(nb.Segments, old.Segments) && old.Grantee == nb.Grantee' 'f.Contained = f.Contained && old.Grantee == nb.Grantee' "a renewal need not contain its predecessor"
mut authz/change.go 'len(next.Segments) == 0 || !coversAll(cur.Segments, next.Segments) {' 'len(next.Segments) == 0 {' "a narrowing may widen"
mut authz/change.go 'if req.ExpectedRevision != nil && req.ExpectedRevision.Value != strconv.FormatInt(t.Revision, 10) {' 'if false {' "the content revision is not compared (row 17)"
mut authz/change.go 'if req.ExpectedStateRevision != nil && req.ExpectedStateRevision.Value != strconv.FormatInt(t.StateRevision, 10) {' 'if false {' "the state revision is not compared (row 4)"
mut authz/change.go 'if p.target == nil && p.kind == Widen && p.recType != "" { // a new widening rejected for good: ended (rejected)' 'if false { // a new widening rejected for good: ended (rejected)' "a new widening rejected for good keeps no record"
mut authz/change.go '			if relinquish && !manages(unitOf) {' '			if true {' "a manager's revocation is recorded as relinquished"
mut authz/change.go '	if v.Row == 2 {
		return false
	}' '' "a conflict binds the key again"
mut authz/change.go 'f.FromState = slices.Contains([]string{"requested", "awaiting_confirmation", "scheduled"}, t.State)' 'f.FromState = true' "an effective record can be terminated"
mut authz/security.go 'AND (valid_until IS NULL OR valid_until > now())' 'AND true' "a record past its validity still gives access"
