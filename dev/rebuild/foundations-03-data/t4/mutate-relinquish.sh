#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (D82: relinquishing one's own records): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (D82 relinquish), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/view.go '	if component == ID { // D82' '	if false && component == ID { // D82' "no fixed segment: a holder cannot relinquish"
mut authz/view.go '		self := map[string]sdkauthz.Atom{Holder: {Kind: "self"}}' '		self := map[string]sdkauthz.Atom{Holder: {Kind: "all"}}' "the fixed segment covers everyone's records"
mut authz/module.go '	return sdkauthz.Facts{Holder: {State: "value", Value: holder}}, nil' '	return sdkauthz.Facts{Holder: {State: "value", Value: holder + "x"}}, nil' "the holder fact is not the record's"
mut authz/module.go '	ctx, plan, err := s.List(c.Ctx(), OpRead, "r", 1)' '	ctx, plan, err := s.List(c.Ctx(), OpRead, "r", 1)
	plan.Where = "TRUE"' "the listing shows every record"
mut authz/module.go '	if in.Direction != Tighten || in.Target == "" || in.Termination != "" || len(in.Candidate) > 0 {' '	if in.Direction != Tighten || in.Target == "" {' "a relinquishment may be a termination or a narrowing"
echo "done" >> "$out"
