#!/usr/bin/env bash
# Mutation runs for infra/authz's tightening-only operations (T5e: the tightening route, T_tight on the last applied
# facts, confirmers by the last applied facts, objects that touch an admin's availability, the basis in the result
# and the audit): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.18 in progress (T5e), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
R=authz/requester.go; C=authz/confirm.go; F=authz/facts.go; M=authz/module.go; D=authz/decide.go; T=authz/target.go; E=authz/effect.go
mut $R '	return !j.HasWatermark || j.Age > tight || j.SourceState == projection.Stalled' '	return !j.HasWatermark || j.Age > tight' "a stalled source needs no second person"
mut $R '	return !j.HasWatermark || j.Age > tight || j.SourceState == projection.Stalled' '	return j.Age > tight || j.SourceState == projection.Stalled' "no watermark needs no second person"
mut $R '	a.beyondTight = beyondTight(lj, m.tight)' '	a.beyondTight = false' "never beyond T_tight"
mut $R '	a.last = l == proven' '	a.last = false' "no last applied facts: every stale tightening refused"
mut $D '(f.TightenNeedsConfirmation || f.Eligible != proven && f.BeyondTight)' 'f.TightenNeedsConfirmation' "row 21 ignores the two-person rule"
mut $C '	if lastApplied && a.now == unprovable && a.last && !a.quarantined {' '	if false && a.now == unprovable && a.last && !a.quarantined {' "confirmers only proven now"
mut $C '			lastApplied := t.State != "awaiting_confirmation" && !affects' '			lastApplied := false && !affects' "a confirmation is not recorded by the last applied facts"
mut $F '	if p.confirmed, err = m.confirmationsOf(ctx, tx, req.ConfirmationIDs, t, requester, holderOf, !f.AffectsAdmins, f); err != nil {' '	if p.confirmed, err = m.confirmationsOf(ctx, tx, req.ConfirmationIDs, t, requester, holderOf, false, f); err != nil {' "an attached confirmer is judged now only"
mut $F '	if p.confirmed, err = m.confirmationsOf(ctx, tx, req.ConfirmationIDs, t, requester, holderOf, !f.AffectsAdmins, f); err != nil {' '	if p.confirmed, err = m.confirmationsOf(ctx, tx, req.ConfirmationIDs, t, requester, holderOf, true, f); err != nil {' "a confirmer of an admin's holding by the last applied facts"
mut $T '	case "management_unit":
		recs, err := active(ctx, tx, "management_holding")' '	case "management_unit_":
		recs, err := active(ctx, tx, "management_holding")' "a unit never touches an admin"
mut $T '				if u = units[u].Parent; u == "" {' '				if u = ""; u == "" {' "only the unit an admin holding sits in, not those above"
mut $F '	if f.Eligible == unprovable {
		p.basis = f.Basis
	}' '' "the basis is not carried"
mut $E '	for k, v := range basis {
		changes[k] = v
	}' '' "the audit does not say its basis"
mut authz/enact.go 'm.applied(ctx, tx, e.operation(), e.requester,' 'm.applied(ctx, tx, OpChange, e.requester,' "the audit names the change operation"
mut $M '	if in.Direction == Tighten {
		return errs.New(errs.ReasonRequestInvalid, "a tightening goes to POST /api/authz/tightenings ("+OpTighten+")")
	}' '' "the changes take a tightening"
mut $M '	ctx, _, err := s.Check(c.Ctx(), OpTighten, facts)' '	ctx, _, err := s.Check(c.Ctx(), OpChange, facts)' "a tightening checks the change operation"
mut $C '			if state == "awaiting_confirmation" {
				op = OpChange
			}' '' "a saved widening is confirmed with the tightening operation"
mut $C '	op := OpTighten
	if uuidText' '	op := OpChange
	if uuidText' "a tightening is confirmed with the change operation"
echo "done" >> "$out"
