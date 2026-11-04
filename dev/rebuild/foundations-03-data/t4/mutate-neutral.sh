#!/usr/bin/env bash
# Mutation runs for infra/authz's neutral changes (T4e): each rule broken by one edit, the integration tests run,
# the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4e, neutral changes), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q "^--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "Error:|Messages:|Error Trace:" -A1 | grep -v '^--$\|"level"' | grep -E "Error:|Messages:|_test.go" | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/enact.go 'UPDATE authz_record SET body = $2, revision = revision + 1, last_change = $3,' 'UPDATE authz_record SET body = $2, revision = revision + 1, state_revision = state_revision + 1, last_change = $3,' "a neutral change advances the state revision"
mut authz/enact.go 'if err := m.audited(ctx, tx, e.requester, Neutral, p.target.Type, id, ""); err != nil {' 'if _, err := m.applied(ctx, tx, e.requester, Neutral, p.target.Type, id); err != nil {' "a neutral change advances the security revision"
mut authz/enact.go 'if err := m.audited(ctx, tx, e.requester, Neutral, p.target.Type, id, ""); err != nil {' 'if err := error(nil); err != nil {' "a neutral change is not audited"
mut authz/target.go '	if string(a) != string(b) { // encoding/json sorts map keys' '	if false { // encoding/json sorts map keys' "a neutral change may change more than the name"
mut authz/facts.go 'structural, p.body = s.manages(unitOf) || (t.Type == "role_revision" || unitOf == "") && s.admin, renamed' 'structural, p.body = true, renamed' "anyone may make a neutral change"
mut authz/target.go 'next.Parent != cur.Parent || next.Name != cur.Name || cur.Root ||' 'next.Parent != cur.Parent || cur.Root ||' "a narrowing may rename"
mut authz/facts.go '		f.FromState = t.State != "ended"
		if req.CandidateDigest' '		f.FromState = true
		if req.CandidateDigest' "an ended record may be renamed (row 4)"
echo "done" >> "$out"
