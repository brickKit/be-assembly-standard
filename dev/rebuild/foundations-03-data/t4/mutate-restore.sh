#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (T4g, part 3: uncomputable and its restore): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4g part 3, uncomputable and its restore), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/facts.go '	f.PartlyOutside = !lim.covers(segs, grantee)' '	f.PartlyOutside = false && !lim.covers(segs, grantee)' "a partly outside restore is not marked for review (row 30)"
mut authz/closure.go '		if _, err := m.rt.Work.Enqueue(ctx, tx, JobDue, firing{Record: id, StateRevision: t.StateRevision,
			Trigger: triggerRestore}); err != nil {' '		if _, err := m.rt.Work.Enqueue(ctx, tx, JobDue, firing{Record: id, StateRevision: t.StateRevision,
			Trigger: triggerRestore}); false && err != nil {
			return err
		}
		if err := error(nil); err != nil {' "a computable held record registers no restore"
mut authz/enact.go '	case p.restore: // held (uncomputable) back to active; partly outside: to be reviewed (row 30)
		id = p.target.ID
		if stateRev, err = m.transition(ctx, tx, id, "active", "", "", change, ""); err != nil {' '	case p.restore: // held (uncomputable) back to active; partly outside: to be reviewed (row 30)
		id = p.target.ID
		if stateRev, err = m.transition(ctx, tx, id, "held", "", "uncomputable", change, ""); err != nil {' "an applied restore leaves the record held"
mut authz/enact.go '	if t := p.target; t != nil && p.kind == Tighten && p.endReason == "" && t.State == "held" && t.HoldReason == "uncomputable" {' '	if t := p.target; false && t != nil && p.kind == Tighten && p.endReason == "" && t.State == "held" && t.HoldReason == "uncomputable" {' "a held record narrowed is not looked at again (CP115)"
mut authz/scheduled.go '	case triggerRestore:
		return "held"' '	case triggerRestore:
		return "scheduled"' "a restore starts from the wrong state (row 3 voids it)"
echo "done" >> "$out"
