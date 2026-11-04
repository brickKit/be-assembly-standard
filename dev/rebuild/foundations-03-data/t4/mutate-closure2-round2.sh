#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (T4g, part 2: accounts and expiry): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1
echo "round 2, $(date -I): the three that did not compile, rewritten." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
C=authz/closure.go
mut authz/module.go 'return m.closeAfter(ctx, tx, "account", principal) }' 'return nil }' "an account's change registers no closure"
mut $C '		return rec.Status == "disabled" && !mark, true, nil' '		return false && !mark, true, nil' "a disabled account ends nothing"
mut $C '		return rec.Status == "disabled" && !mark, true, nil' '		return rec.Status != "active" || mark, true, nil' "a frozen account ends its records"
echo "done round 2" >> "$out"
