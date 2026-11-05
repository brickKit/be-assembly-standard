#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.25 in progress (T9d): each rule of the account status changes broken by one
# edit, go test -tags integration ./authz/ -run TestAccountStatusChanges, the file restored. Run from
# components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.25 in progress (T9d, third round: the filter of the other available admins and the CP108 attribution, after the new assertion found the attribution wrong), $(date -I): each rule broken by one edit; go test -tags integration ./authz/ -run TestAccountStatusChanges; the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/maa.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/maa.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ -run TestAccountStatusChanges 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "Error:|Messages:" | grep -v '"level"' | head -2 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/maa.bak "$f"; }
A=authz/accountchange.go; E=authz/effect.go
C=authz/confirm.go
mut $C "		AND record_type = 'management_holding' AND body->>'system_role' = 'authorization_admin' AND NOT coalesce((body->>'confirmation_backfill_pending')::boolean, false)" "		AND record_type = 'management_holding' AND body->>'system_role' = 'authorization_admin'" "a holding pending confirmation counts as another available admin"
mut authz/cooling.go "state <> 'active' AND coalesce(last_change LIKE" "coalesce(last_change LIKE" "a requester's release counts as making an admin awaiting a reconfirmation unavailable (CP108)"
echo "done" >> "$out"
