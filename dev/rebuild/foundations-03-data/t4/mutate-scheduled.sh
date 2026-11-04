#!/usr/bin/env bash
# Mutation runs for infra/authz's scheduled widenings (T4d): each rule broken by one edit, the integration tests
# run, the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.17 in progress (T4d), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q "^--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "Error:|Messages:|Error Trace:" -A1 | grep -v '^--$\|"level"' | grep -E "Error:|Messages:|_test.go" | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/facts.go 'f.FromState, f.FromRevision = t.State == e.job.from(), t.StateRevision == e.job.StateRevision' 'f.FromState, f.FromRevision = t.State == e.job.from(), true' "a job's state revision is not compared (row 3)"
mut authz/facts.go 'f.FromState, f.FromRevision = t.State == e.job.from(), t.StateRevision == e.job.StateRevision' 'f.FromState, f.FromRevision = true, t.StateRevision == e.job.StateRevision' "a job's start state is not compared (row 3)"
mut authz/scheduled.go 'e := entry{namespace: ID,' 'e := entry{namespace: "",' "the derived key is bound outside the member's namespace"
mut authz/facts.go '		if err := m.supersedes(ctx, tx, t.Predecessor, true, f, p); err != nil {
			return false, nil, err
		}
	}
	return structural, nil, nil' '		if err := m.supersedes(ctx, tx, t.Predecessor, true, f, p); err != nil {
			return false, nil, err
		}
	}
	return true, nil, nil' "a job does not recheck the requester's standing (CP68)"
mut authz/scheduled.go 'if res, _, err = m.effect(ctx, tx, e); err == nil && res.Outcome == "processing" {' 'if res, _, err = m.effect(ctx, tx, e); false {' "processing completes the job instead of waiting"
mut authz/enact.go '	if state == "scheduled" {' '	if false {' "no timed work item is registered"
mut authz/enact.go '			*p.at); err != nil {' '			(*p.at).AddDate(0, 0, -1)); err != nil {' "the work item is due a day early (at once)"
mut authz/enact.go '		case p.activate: // a job' '		case false: // a job' "a job's final rejection leaves the record scheduled"
mut authz/facts.go 'p.at, f.Future = &at, at.After(time.Now())' 'p.at, f.Future = &at, false' "a future widening applies at once"
mut authz/facts.go '		if stored {
			f.RevisionsChanged = true' '		if false {
			f.RevisionsChanged = true' "a predecessor ended before the job voids it instead of rejecting (A122)"
mut authz/enact.go 'if p.successor != "" && (p.activate || p.target == nil) {' 'if p.successor != "" && p.target == nil {' "a renewal taking effect when due leaves its predecessor active"
mut authz/facts.go '		if p.to != nil && !p.to.After(at) {' '		if false {' "a validity that ends before effective_from is accepted"
echo "done" >> "$out"
