#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (T4 acceptance: the cases added for CP81, CP91, CP98): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4 acceptance cases), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/facts.go '			f.TerminatorEligible = requester == t.RequestedBy' '			f.TerminatorEligible = false && requester == t.RequestedBy' "an applicant who lost eligibility cannot withdraw (row 7, CP91)"
mut authz/facts.go '			structural, p.endReason = s.manages(unitOf), "cancelled"' '			structural, p.endReason = true, "cancelled"' "anyone may cancel another's pending record (row 8, CP98)"
mut authz/scheduled.go 'func (a firing) key() string { return a.Record + ":" + strconv.FormatInt(a.StateRevision, 10) + ":" + a.Trigger }' 'func (a firing) key() string { return a.Record + ":" + a.Trigger + strconv.FormatInt(0*a.StateRevision, 10) }' "the derived key has no state revision (CP81)"
echo "done" >> "$out"
