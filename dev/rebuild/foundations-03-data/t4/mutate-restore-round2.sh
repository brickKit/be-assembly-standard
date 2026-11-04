#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (T4g, part 3: uncomputable and its restore): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1
echo "round 2, $(date -I): round 1 found a closure storm (a scan going on to every unit, each scanning again) that re-marked the restored grant; fixed (a scan does not cascade) and tested. The review mutant again, the enqueue mutant rewritten (round 1 still called Enqueue), the storm as a mutant." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/facts.go '	f.PartlyOutside = !lim.covers(segs, grantee)' '	f.PartlyOutside = false && !lim.covers(segs, grantee)' "a partly outside restore is not marked for review (row 30)"
mut authz/closure.go '		if _, err := m.rt.Work.Enqueue(ctx, tx, JobDue, firing{Record: id, StateRevision: t.StateRevision,
			Trigger: triggerRestore}); err != nil {' '		if _, err := (firing{Record: id, StateRevision: t.StateRevision,
			Trigger: triggerRestore}), error(nil); err != nil {' "a computable held record registers no restore"
mut authz/closure.go '	if t.Type == "management_unit" && cascade {' '	if t.Type == "management_unit" {' "a scan goes on to every unit's closure (the storm)"
echo "done round 2" >> "$out"
