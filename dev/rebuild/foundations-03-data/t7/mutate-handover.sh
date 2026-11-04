#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.21 (T7c: handover, recall and role bindings): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.21 in progress (T7c), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
F=authz/facts.go; G=authz/delegate.go
mut $F '		f.Contained = f.Contained && coversAll(nb.Segments, old.Segments) && old.Grantee == nb.Grantee' '		f.Contained = f.Contained && old.Grantee == nb.Grantee' "a rebinding need not contain the old grant"
mut $F '		structural, p.body = s.admin, b' '		structural, p.body = true, b' "any manager edits roles"
mut $G '	for u, n := unit, 0; n <= len(s.units); u, n = s.units[u].Parent, n+1 {' '	for u, n := unit, 0; n < 1; u, n = s.units[u].Parent, n+1 {' "a holding manages its own unit only, nothing below"
mut $G '		return ActRevoke' '		return ActGrant' "a grant's tightening takes grant"
echo "done" >> "$out"
