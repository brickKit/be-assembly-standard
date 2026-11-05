#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.25 in progress (T9d): each rule of the account status changes broken by one
# edit, go test -tags integration ./authz/ -run TestAccountStatusChanges, the file restored. Run from
# components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.25 in progress (T9d, second round: the survivor after the test released the identity-side disposition, so the holding is active and only pending), $(date -I): each rule broken by one edit; go test -tags integration ./authz/ -run TestAccountStatusChanges; the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/maa.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/maa.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ -run TestAccountStatusChanges 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "Error:|Messages:" | grep -v '"level"' | head -2 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/maa.bak "$f"; }
A=authz/accountchange.go; E=authz/effect.go
mut $E '		if h.Holder == principal && !h.BackfillPending {' '		if h.Holder == principal {' "a holding pending confirmation still qualifies"
echo "done" >> "$out"
