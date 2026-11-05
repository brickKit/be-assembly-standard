#!/usr/bin/env bash
# Mutation runs for infra/iam-casdoor 3.0.22 in progress (T9c): each rule of the account operations broken by one
# edit, go test -tags integration ./iam/ against the real Casdoor, the file restored. Run from
# components/infra/iam-casdoor with iamenv.sh sourced.
out=$1; : > "$out"
echo "infra/iam-casdoor 3.0.22 in progress (T9c, third round: the UNPROVABLE verdict of contract alpha.4), $(date -I): each rule broken by one edit; go test -tags integration ./iam/; the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/mi3.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./iam >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/mi3.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./iam/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "Error:|Messages:" | grep -v '"level"' | head -2 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/mi3.bak "$f"; }
A=iam/accountops.go
mut $A '	case authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_UNPROVABLE: // security 03: nothing saved, ask again later' '	case -4:' "a confirmer not provable now is a refusal, not processing (CP92)"
echo "done" >> "$out"
