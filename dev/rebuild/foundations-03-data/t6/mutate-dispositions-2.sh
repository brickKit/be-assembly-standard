#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6a: security dispositions, A128): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6a), second round: the survivor after its test, and the two mutants that did not compile, rewritten, $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
D=authz/disposition.go
mut $D '	return s.manages(domain), nil, nil' '	return true, nil, nil' "anyone disposes"
mut $D '			if slices.ContainsFunc(segs, func(sg sdkauthz.Segment) bool { return suspended(scope, sg, in.Subject) }) {' '			if false && slices.ContainsFunc(segs, func(sg sdkauthz.Segment) bool { return suspended(scope, sg, in.Subject) }) {' "no grant is held"
mut $D '		if why != "" {
			return false, &changeResult{' '		if false && why != "" {
			return false, &changeResult{' "the scope need not be within the limit"
echo "done" >> "$out"
