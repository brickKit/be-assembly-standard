#!/usr/bin/env bash
# Mutation runs for infra/authz's confirmation records (T5b-T5d: protected operations, the owner's confirmation, applying once confirmed): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.18 in progress (T5b-T5d), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
C=authz/confirm.go; F=authz/facts.go
mut $F '		f.NeedsConfirmation = true // a protected operation: a new or enlarged management unit' '		f.NeedsConfirmation = false // a protected operation: a new or enlarged management unit' "a new unit needs no confirmation"
mut $F '		f.NeedsConfirmation = true // a protected operation: a management holding' '		f.NeedsConfirmation = false // a protected operation: a management holding' "a holding needs no confirmation"
mut $F '				f.TightenNeedsConfirmation = h.Holder != requester' '				f.TightenNeedsConfirmation = false && h.Holder != requester' "tightening another admin's holding needs no confirmation"
mut $C '			if !o.Verify(key, in.Signature) {' '			if false && !o.Verify(key, in.Signature) {' "the owner's signature is not checked"
mut $C '			if err != nil || !at.After(time.Now()) || at.After(by.Add(time.Minute)) {' '			if err != nil || !at.After(time.Now()) {' "the owner's signature may stretch a confirmation's life"
mut $C '		if err != nil || others {
			return disproven, err' '		if err != nil || false && others {
			return disproven, err' "the owner's key stands in for an available admin on a widening"
mut $C '		if t.State == "awaiting_confirmation" { // the saved widening goes to the effect point (T5c)' '		if false && t.State == "awaiting_confirmation" { // the saved widening goes to the effect point (T5c)' "a confirmation brings nothing to the effect point"
mut authz/enact.go '		if p.activate && e.job.Trigger == triggerConfirmed { // confirmed, effective later' '		if false && p.activate && e.job.Trigger == triggerConfirmed { // confirmed, effective later' "confirmed and effective later is not scheduled"
mut $F '			f.TerminatorEligible, structural = ok == proven, ok != disproven' '			f.TerminatorEligible, structural = false, ok != disproven' "a confirmer cannot reject"
mut $F '			if requester == t.RequestedBy || requester == holderOf {' '			if requester == holderOf {' "the applicant rejects her own request as its confirmer"
mut $F '	if p.confirmed, err = m.confirmationsOf(ctx, tx, nil, t, e.requester, recordHolder(t), f); err != nil {' '	if p.confirmed, err = []string(nil), error(nil); err != nil {' "a job does not look at its record's confirmations"
mut $C '	case !widening && len(invalid) > 0, widening && len(holding) == 0 && len(unprovableIDs) == 0:' '	case len(invalid) > 0:' "on a saved widening one confirmation that does not hold spoils the rest"
echo "done" >> "$out"
