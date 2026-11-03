#!/usr/bin/env bash
# Mutation runs for infra/authz's new effect point (T4a-T4c): each rule broken by one edit, TestMemberEndToEnd run,
# the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1
echo "Round 2 ($(date -I)): the three survivors, after the test sharpened them (a stale state revision alone; an active record cancelled; a record past its validity)." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q "^--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "Error:|Messages:" -A1 | grep -v '^--$\|"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/change.go 'if req.ExpectedStateRevision != nil && req.ExpectedStateRevision.Value != strconv.FormatInt(t.StateRevision, 10) {' 'if false {' "the state revision is not compared (row 4)"
mut authz/change.go 'f.FromState = slices.Contains([]string{"requested", "awaiting_confirmation", "scheduled"}, t.State)' 'f.FromState = true' "an effective record can be terminated"
mut authz/security.go 'AND (valid_until IS NULL OR valid_until > now())' 'AND true' "a record past its validity still gives access"
