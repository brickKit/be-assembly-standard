#!/usr/bin/env bash
# Mutation runs for be-sdk-go alpha.71 in progress (T8a, second round: the two survivors after the new vector case and the fixed digest test; two rewritten mutants that did not compile): each rule broken by one edit, the packages' unit and
# integration tests run against the local be-protocol (GOWORK), the file restored. Run from tools/be-sdk-go with
# itenv.sh sourced and GOWORK set.
out=$1; : > "$out"
echo "be-sdk-go alpha.71 in progress (T8a), $(date -I): each rule broken by one edit; go test -tags integration -p 1 ./authz/ ./list/ ./records/ ./launcher/ (launcher: TestOthersSeeNothingAndFieldsFollowTheSegments only); the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz ./list ./records ./launcher >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$( { go test -count=1 -tags integration -p 1 ./authz/ ./list/ ./records/ 2>&1; go test -count=1 -tags integration ./launcher/ -run TestOthersSeeNothingAndFieldsFollowTheSegments 2>&1; } )
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
E=authz/eval.go; S=authz/subject.go; G=authz/segment.go; RF=authz/refuse.go; Q=authz/sql.go; L=list/list.go; RC=records/records.go; H=internal/host/build.go
mut $G '		if !ok {
			return fmt.Errorf("segment for %s: dimension %s is not declared", s.Operation, dim)' '		if !ok && false {
			return fmt.Errorf("segment for %s: dimension %s is not declared", s.Operation, dim)' "an undeclared dimension passes (EN08)"
mut $L ', "readable_only": q.ReadableOnly})' '})' "the narrowing is not in the filter digest"
mut $S '		case !declared || fd.Class == Secret:' '		case !declared || fd.Class == "never":' "a secret field is masked instead of dropped"
mut $Q '		if slices.Contains(set, field) {' '		if slices.Contains(set, field) || true {' "readable_only keeps rows that do not show the field (FX12)"
echo "done" >> "$out"
