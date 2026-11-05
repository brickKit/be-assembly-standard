#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.25 in progress (T9d): each rule of the account status changes broken by one
# edit, go test -tags integration ./authz/ -run TestAccountStatusChanges, the file restored. Run from
# components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.25 in progress (T9d), $(date -I): each rule broken by one edit; go test -tags integration ./authz/ -run TestAccountStatusChanges; the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/maa.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/maa.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ -run TestAccountStatusChanges 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "Error:|Messages:" | grep -v '"level"' | head -2 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/maa.bak "$f"; }
A=authz/accountchange.go; E=authz/effect.go
mut $A '	need := map[bool]string{true: "protected: the account holds the authorization admin role"}[admin]' '	need := ""' "an admin's account is not protected (CP96)"
mut $A '	if need == "" && in.GetSecondPerson() {' '	if need == "" && in.GetSecondPerson() && false {' "the two-person rule beyond T_tight is ignored (CP80)"
mut $A '	case c.confirmer == in.GetRequester() || c.confirmer == in.GetAccount():' '	case c.confirmer == in.GetAccount():' "the requester confirms their own request"
mut $A '		FROM authz_confirmation WHERE id = $1 AND account = $2 AND target_state = $3 AND target_state_version = $4`,' '		FROM authz_confirmation WHERE id = $1 AND account = $2 AND $3::text IS NOT NULL AND target_state_version = $4`,' "a confirmation of another status counts"
mut $A '	err := tx.QueryRow(ctx, `SELECT confirmer, basis, consumed_by_change IS NULL AND expires_at > now()' '	err := tx.QueryRow(ctx, `SELECT confirmer, basis, true' "a used or expired confirmation counts"
mut $A '			if _, err := tx.Exec(ctx, "UPDATE authz_confirmation SET consumed_by_change = $2 WHERE id = $1", rec.Confirmation,' '			if _, err := tx.Exec(ctx, "SELECT $1::text, $2::text", rec.Confirmation,' "the account status does not use its confirmation"
mut $A '		return setBackfill(ctx, tx, principal, true, ref)' '		return nil' "a console re-enable leaves the holding available (CP42)"
mut $A '		return setBackfill(ctx, tx, principal, false, ref)' '		return nil' "a confirmed re-enable leaves it pending"
mut $E '		if h.Holder == principal && !h.BackfillPending {' '		if h.Holder == principal {' "a holding pending confirmation still qualifies"
mut $A '		case authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_CONFIRMATION_REQUIRED:' '		case authzv3.AccountChangeVerdict(99):' "a reconfirmation without a confirmation goes through"
mut $A '		case others:' '		case others && false:' "the owner stands in on a re-enable while another admin is available"
echo "done" >> "$out"
