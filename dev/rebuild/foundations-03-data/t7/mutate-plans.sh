#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.21 (T7d: batch plans, A132): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.21 in progress (T7d), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
P=authz/plan.go; R=authz/planrun.go; H=authz/planhttp.go; F=authz/facts.go; E=authz/enact.go; V=authz/recovery.go
mut $F '	if e.planItem && (!f.FromState || !f.FromRevision) { // the target moved since the preview: row 17 (security 08)' '	if false && e.planItem && (!f.FromState || !f.FromRevision) { // the target moved since the preview: row 17 (security 08)' "a moved target voids the item (row 3)"
mut $R '	case res.Outcome == "rejected" && res.Reason == errs.ReasonChangeRevisionStale: // row 17
		return itemNeedsReview, false' '' "row 17 rejects the item"
mut $R '	case res.Outcome == "awaiting_confirmation": // saved (row 20, followed by its record) or a confirmation missing
		return itemNeedsReview, false' '' "awaiting confirmation rejects the item"
mut $E '	return rev, m.followRecord(ctx, tx, id, state) // a plan item waiting on it (planrun.go)' '	return rev, nil' "items do not follow their records"
mut $R '	next := map[string]string{"active": itemApplied, "scheduled": itemApplied, "ended": itemRejected}[state]' '	next := map[string]string{"scheduled": itemApplied, "ended": itemRejected}[state]' "an effective record does not apply its item"
mut $R '	if rejected > 0 {
		state = planPartial
	}' '' "a plan with rejected items completed"
mut $R '	for _, id := range saved {
		if _, err := m.transition(ctx, tx, id, "ended", "cancelled", "", change, "plan "+state); err != nil {
			return err
		}
	}' '	_ = change' "an ended plan leaves its saved records"
mut $R "ELSE 'not_reviewed' END" "ELSE 'plan_terminated' END" "items to be reviewed end as terminated"
mut $R '		if p.ExpiresAt != nil && !time.Now().Before(*p.ExpiresAt) {
			return m.endPlan(ctx, tx, p, planExpired)
		}' '' "a run after the expiry goes on"
mut $R '		if p.Second != "" && p.Second != ownerName {' '		if false && p.Second != "" && p.Second != ownerName {' "the second confirmer not checked when an item runs"
mut $R '	return "plan:" + plan + ":" + item + ":" + strconv.Itoa(attempt)' '	return "plan:" + plan + ":" + item + ":" + strconv.Itoa(1+0*attempt)' "an item runs again under its first key"
mut $H '		case in.PreviewDigest != p.PreviewDigest:' '		case false:' "a confirmation of another preview"
mut $H '	if n <= m.planConfirmAbove {' '	if n <= m.planConfirmAbove+100 {' "no second person above the threshold"
mut $H '	if confirmer == p.Initiator {
		return "", time.Time{}, errs.New(errs.ReasonPermissionDenied, "the initiator does not confirm their own plan")
	}' '' "the initiator confirms their own plan"
mut $H '		if it.State != itemNeedsReview || it.Record != "" {' '		if it.State != itemNeedsReview {' "an item with a saved record runs again"
mut $P '	if total > budgetPlanComparisons {' '	if total > budgetPlanComparisons*10 {' "no comparison budget"
mut $P '		r.ExpectedRevision = &revisionRef{Domain: contentDomain, Value: strconv.FormatInt(t.Revision, 10)}' '		_ = contentDomain' "the target's content revision not recorded"
mut $P '	case err == nil && was == digest:
		return id, nil' '' "the same plan key again conflicts"
mut $P '	case r.ChangeKey != "":' '	case false:' "an item keeps its own change key"
mut $V '		if err := reviewReplaced(ctx, tx, h.Holder); err != nil {' '		if err := error(nil); err != nil {' "a replaced admin's plans run on"
echo "done" >> "$out"
