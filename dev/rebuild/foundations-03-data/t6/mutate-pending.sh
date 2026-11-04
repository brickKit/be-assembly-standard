#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6e: pending recovery): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6e), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
P=authz/pending.go; F=authz/facts.go; G=authz/change.go
mut $P '	case avail == proven:
		return nil
	}' '	case avail == proven || true:
		return nil
	}' "never pending"
mut $P '		AND body->>'"'"'system_role'"'"' = '"'"'authorization_admin'"'"')`).Scan(&claimed); err != nil || !claimed {' '		AND body->>'"'"'system_role'"'"' = '"'"'authorization_admin'"'"')`).Scan(&claimed); err != nil || claimed {' "pending only before the claim"
mut $F '	f.RecoveryPending = st != stateOperational // rows 13-14 (T6e)' '	f.RecoveryPending = false // rows 13-14 (T6e)' "the management structure widens while pending"
mut $G '	if res.Outcome == "applied" && f.AffectsAdmins { // an admin may have become unavailable (T6e)' '	if false && res.Outcome == "applied" && f.AffectsAdmins { // an admin may have become unavailable (T6e)' "a change at the effect point is not judged"
mut $P '		case hold == "security_hold":
			u.Cause = "security_disposition"' '		case hold == "security_hold_":
			u.Cause = "security_disposition"' "a disposition's hold is not its cause"
echo "done" >> "$out"
