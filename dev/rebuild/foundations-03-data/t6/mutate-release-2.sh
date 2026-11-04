#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6b: releasing a security disposition): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6b), second round: the survivors after their tests, and the two mutants that did not compile, rewritten, $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
R=authz/release.go
mut $R '	return e.requester != d.Subject && s.manages(domain), nil, nil' '	return e.requester != d.Subject && (s.manages(domain) || true), nil, nil' "a smaller domain releases it (CP53)"
mut $R '	f.FromState = d.State == "active"' '	f.FromState = true' "a released disposition again"
mut $R '		case !restorable(t, lims):' '		case false && !restorable(t, lims):' "nothing is kept held (CP66)"
mut $R '		if !c.Live || c.Disposition != d.ID || c.Revision != d.Revision || c.Confirmer == requester || c.Confirmer == d.Subject {' '		if !c.Live || c.Confirmer == requester || c.Confirmer == d.Subject {' "a confirmation of another disposition counts"
echo "done" >> "$out"
