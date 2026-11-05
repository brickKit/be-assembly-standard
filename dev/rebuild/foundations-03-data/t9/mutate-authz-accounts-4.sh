#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.25 in progress (T9d): each rule of the account status changes broken by one
# edit, go test -tags integration ./authz/ -run TestMemberEndToEnd, the file restored. Run from
# components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.26 in progress (CP80 and CP92 account forms in the stale phase; second round, the two mutants that did not compile rewritten), $(date -I): each rule broken by one edit; go test -tags integration ./authz/ -run TestMemberEndToEnd; the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/maa.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/maa.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ -run TestMemberEndToEnd 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "Error:|Messages:" | grep -v '"level"' | head -2 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/maa.bak "$f"; }
C=authz/accountchange.go
mut $C "	case ok == unprovable:
		return authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_UNPROVABLE" "	case ok == -99:
		return authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_UNPROVABLE" "a confirmer not provable now is a refusal, not undecided (CP92)"
mut $C "		!admin && in.TargetState != \"active\")" "		false && !admin && in.TargetState != \"active\")" "an ordinary account's tightening is not confirmed on the last applied facts (CP80)"
mut $C "		!admin && in.TargetState != \"active\")" "		true || !admin && in.TargetState != \"active\")" "an admin's account is confirmed on the last applied facts (CP92)"
mut $C "	switch ok, err := m.confirmerEligible(ctx, tx, c.confirmer, !admin && in.GetTargetState() != \"active\"); {" "	switch ok, err := m.confirmerEligible(ctx, tx, c.confirmer, true); {" "an admin's account is judged on a confirmer's last applied facts (CP92)"
echo "done" >> "$out"
