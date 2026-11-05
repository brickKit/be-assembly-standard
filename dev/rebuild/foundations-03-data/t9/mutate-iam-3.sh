#!/usr/bin/env bash
# Mutation runs for infra/iam-casdoor 3.0.22 in progress (T9c): each rule of the account operations broken by one
# edit, go test -tags integration ./iam/ against the real Casdoor, the file restored. Run from
# components/infra/iam-casdoor with iamenv.sh sourced.
out=$1; : > "$out"
echo "infra/iam-casdoor 3.0.22 in progress (T9c, second round after the fence tests and a safer other-issuer account), $(date -I): each rule broken by one edit; go test -tags integration ./iam/; the file restored." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/mi3.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./iam >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/mi3.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./iam/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "Error:|Messages:" | grep -v '"level"' | head -2 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/mi3.bak "$f"; }
A=iam/accountops.go; R=iam/reconcile.go; ST=iam/store.go
mut $A '	verdict, err := m.checkChange(ctx, a, target, requester, in.Confirmation, secondPerson(since, stale, time.Now(), m.tight))' '	verdict, err := &authzv3.CheckAccountChangeResponse{Verdict: authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_ALLOWED}, error(nil); _, _ = since, stale' "the authorization member is not asked"
mut $A '	case authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_ALLOWED:
	case authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_CONFIRMATION_REQUIRED:' '	case authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_ALLOWED, authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_CONFIRMATION_REQUIRED:
	case -1:' "a confirmation required is taken as allowed"
mut $A '	default:
		return errs.New(errs.ReasonPermissionDenied' '	case -2:
		return errs.New(errs.ReasonPermissionDenied' "a refusal is taken as allowed"
mut $A '	confirmation := in.Confirmation' '	confirmation := ""' "the confirmation does not go out"
mut $ST '		status_confirmation = NULLIF($2, '"''"')::uuid WHERE principal = $1' '		status_confirmation = coalesce(NULLIF($2, '"''"')::uuid, status_confirmation) WHERE principal = $1' "a confirmation goes out again with later changes"
mut $A '		if err := m.casdoor.setForbidden(ctx, a.username, true); err != nil {
			m.rt.Logger.Warn' '		if err := error(nil); err != nil {
			m.rt.Logger.Warn' "a disablement does not reach Casdoor"
mut $A '		if err := m.casdoor.setForbidden(ctx, a.username, false); err != nil {
			return err
		}
	}
	version, err' '		if err := error(nil); err != nil {
			return err
		}
	}
	version, err' "an enable does not reach Casdoor"
mut $R '		case !recent && status != "active" && !u.off():' '		case status != "active" && !u.off():' "the comparison takes the member's own change in flight for a rollback"
mut $A '		if _, err := tx.Exec(ctx, `UPDATE iam_account SET status = $2, security_mark = $3, local_change_at = now()' '		if _, err := tx.Exec(ctx, `UPDATE iam_account SET status = $2, security_mark = $3' "a status change here does not fence the comparison"
mut $A '		if err := m.store.fence(ctx, a.principal); err != nil {' '		if err := error(nil); err != nil {' "an enable in flight is not fenced"
mut $A '		if now != on {' '		if false && now != on {' "a change on another version than the one asked about"
mut $A '		_, err = tx.Exec(ctx, "UPDATE iam_account SET product_mfa = $2 WHERE principal = $1 AND product_mfa IS NOT NULL",' '		_, err = tx.Exec(ctx, "SELECT $1::text, $2::text",' "a reset of the second factors is counted twice"
mut $A '	if err := m.casdoor.deleteFactors(ctx, a.username); err != nil {' '	if err := error(nil); err != nil {' "a reset does not remove Casdoor's second factors"
mut $A '	if err := m.casdoor.endSessions(ctx, a.username); err != nil {' '	if err := error(nil); err != nil {' "a forced logout leaves Casdoor's sessions"
mut $A '	if err == nil && a.issuer != m.casdoor.issuer {' '	if false && a.issuer != m.casdoor.issuer {' "another Casdoor's account is changed"
mut $A '	if verdict.GetAdministrator() {
		m.rt.Logger.Error' '	if false {
		m.rt.Logger.Error' "an admin's account status change raises no alert"
mut $A '	return stale && now.Sub(since) > tight' '	return false' "a stale view beyond T_tight needs no second person"
mut $A '	case authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_UNPROVABLE: // security 03: nothing saved, ask again later' '	case -4:' "a confirmer not provable now is a refusal, not processing (CP92)"
echo "done" >> "$out"
