#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6c: identity-side dispositions): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6c), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
S=authz/signal.go; R=authz/release.go
mut $S '	marked := rec.Status == "security_frozen" || rec.Status == "disabled" && (rec.Mark == "compromised" || rec.Mark == "suspicious")' '	marked := rec.Status == "disabled" && (rec.Mark == "compromised" || rec.Mark == "suspicious")' "a freeze is no signal"
mut $S '	marked := rec.Status == "security_frozen" || rec.Status == "disabled" && (rec.Mark == "compromised" || rec.Mark == "suspicious")' '	marked := rec.Status == "security_frozen"' "a mark is no signal"
mut $S '	if first || !marked || ref == last { // first seen; not frozen or marked; the same status again' '	if !marked || ref == last { // first seen; not frozen or marked; the same status again
		_ = first' "an account first seen frozen is a transition"
mut $S '			updated_at = now() WHERE id = $1 AND NOT ($2 = ANY(signal_ref))`, active, ref)' '			updated_at = now() WHERE id = $1 AND false`, active, ref)' "a further mark is not merged"
mut $S '	if was { // still frozen or marked, its disposition released since: no transition (security 08)
		return nil
	}' '	_ = was' "a mark after the release makes a new one"
mut $S '	for _, r := range held {
		if _, err := m.transition(ctx, tx, r, "held", "", "security_hold", change, ""); err != nil {' '	for _, r := range held[:0] {
		if _, err := m.transition(ctx, tx, r, "held", "", "security_hold", change, ""); err != nil {' "nothing is held"
mut $S '	if len(remove) == 0 {
		return nil, false, nil
	}' '' "a release may name no signal"
mut $R '		if len(r.left) > 0 { // signals left: it stays active, what it holds stays held; the confirmations are used' '		if false && len(r.left) > 0 { // signals left: it stays active, what it holds stays held; the confirmations are used' "a partial release releases"
echo "done" >> "$out"
