#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.19 (T5: the cooling-off of a protected widening the owner confirmed, CP108, CP113;
# a bound key answering a saved record's current state, CP61): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.19 in progress (T5 cooling-off, CP61), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
K=authz/cooling.go; C=authz/confirm.go; F=authz/facts.go; G=authz/change.go
mut $K '		if !a.active && a.recent {
			return true, nil
		}
		if a.active {' '		if a.active {' "an admin whose holding ended within the cooling-off is not recent"
mut $K '			if err != nil || acct.now != proven {
				return err == nil, err
			}' '			if err != nil {
				return false, err
			}' "an admin whose account is not proven now is not recent"
mut $K '		if !a.active && a.recent && a.byRequester {' '		if false && !a.active && a.recent && a.byRequester {' "the requester's own doing does not count (CP108)"
mut $K '		if !a.active && a.recent && a.byRequester {' '		if !a.active && a.byRequester {' "the requester's doing counts forever"
mut $K '		if !a.active && a.recent && a.byRequester {' '		if !a.active && a.recent {' "anyone's doing counts as the requester's"
mut $K '	if !t.InCoolingOff || t.State != "scheduled" || requester == t.RequestedBy {' '	if t.State != "scheduled" || requester == t.RequestedBy {' "a veto outside a cooling-off"
mut $K '	ok, err := m.confirmerEligible(ctx, tx, requester, false)
	return ok == proven, err' '	return false, nil' "no veto"
mut $K '	if _, err := tx.Exec(ctx, "UPDATE authz_record SET effective_at = $2, cooling_off_until = $2 WHERE id = $1",' '	if _, err := tx.Exec(ctx, "UPDATE authz_record SET effective_at = $2 WHERE id = $1",' "the cooling-off is not recorded"
mut $K '	_, err := m.rt.Audit.Write(ctx, tx, audit.Record{Category: audit.SecurityChange, Operation: OpChange,
		Outcome: audit.Succeeded, Actor: ID, Target: map[string]any{"type": t.Type, "id": t.ID},
		Changes: map[string]any{"action": "cooling_off", "applicant": t.RequestedBy, "until": canon.Time(until)}})
	return err' '	_, _ = audit.Record{}, canon.Time
	return nil' "the cooling-off is not audited"
mut $F '	if e.job.Trigger == triggerConfirmed && f.OwnerOnly && t.CoolingOff == nil {' '	if false && e.job.Trigger == triggerConfirmed && f.OwnerOnly && t.CoolingOff == nil {' "no cooling-off at all"
mut $F '	if e.job.Trigger == triggerConfirmed && f.OwnerOnly && t.CoolingOff == nil {' '	if e.job.Trigger == triggerConfirmed && t.CoolingOff == nil {' "an independent confirmer's widening cools off too"
mut $C '	return madeUnavailableBy(ctx, tx, requester, requester, object)' '	return false, nil' "othersAvailable ignores CP108"
mut $C '				Changes: map[string]any{"action": "owner_confirmation"}}); err != nil {' '				Changes: map[string]any{"action": "owner"}}); err != nil {' "the owner confirmation is not audited as such"
mut $G '		res, err = current(ctx, tx, res)
		return res, v, err' '		return res, v, err' "a bound key answers the bound result (no CP61)"
mut $G '	case "ended":
		return changeResult{' '	case "ended_":
		return changeResult{' "an ended saved record answers as bound"
echo "done" >> "$out"
