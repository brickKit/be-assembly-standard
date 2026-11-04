#!/usr/bin/env bash
# Round 2 of the T4d mutations: the survivor after the test was sharpened, and the one that did not compile rewritten.
# Appends to the round-1 output. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1
echo "round 2, $(date -I): the work item due at once against the sharpened d1; the requester's standing mutant rewritten to compile." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q "^--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "Error:|Messages:|Error Trace:" -A1 | grep -v '^--$\|"level"' | grep -E "Error:|Messages:|_test.go" | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/enact.go '			*p.at); err != nil {' '			(*p.at).AddDate(0, 0, -1)); err != nil {' "the work item is due a day early (at once)"
mut authz/facts.go '	structural, bad, pre, err := m.widening(ctx, tx, e.requester, t.Type, t.Body, true, s, f, p)' '	structural, bad, pre, err := m.widening(ctx, tx, e.requester, t.Type, t.Body, true, s, f, p)
	structural = true' "a job does not recheck the requester's standing (CP68)"
echo "done round 2" >> "$out"
