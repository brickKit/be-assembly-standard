#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6f: administrator recovery, A129): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6f), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
V=authz/recovery.go; P=authz/pending.go
mut $V '	if err != nil || !ed25519.Verify(key, []byte(d), sig) {' '	if err != nil {' "any signature"
mut $V '	case r.Deployment != m.deployment:' '	case false:' "another deployment's request"
mut $V '		if _, err := tx.Exec(ctx, "INSERT INTO authz_recovery_nonce (nonce, action) VALUES ($1, $2)", r.Nonce, r.Action); err != nil {' '		if _, err := tx.Exec(ctx, "INSERT INTO authz_recovery_nonce (nonce, action) VALUES ($1, $2) ON CONFLICT DO NOTHING", r.Nonce, r.Action); err != nil {' "a request used twice"
mut $V '	if _, err := tx.Exec(ctx, `UPDATE authz_state SET recovery_generation = recovery_generation + 1,' '	if _, err := tx.Exec(ctx, `UPDATE authz_state SET recovery_generation = recovery_generation,' "no new generation"
mut $V '	if len(admins) == 0 {
		units, err := m.units(ctx, tx)' '	if false && len(admins) == 0 {
		units, err := m.units(ctx, tx)' "no admin holding made"
mut $V '	if len(admins) == 0 {
		units, err := m.units(ctx, tx)' '	if len(admins) >= 0 {
		units, err := m.units(ctx, tx)' "a second holding made"
mut $V '		for _, p := range pending {
			if _, err := m.transition(ctx, tx, p, "ended", "cancelled", "", change, ""); err != nil {' '		for _, p := range pending[:0] {
			if _, err := m.transition(ctx, tx, p, "ended", "cancelled", "", change, ""); err != nil {' "the replaced admin's widenings go on"
mut $V '		if _, err := m.transition(ctx, tx, id, "held", "", "security_hold", change, ""); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "UPDATE authz_record SET disposition = $2 WHERE id = $1", id, disp); err != nil {' '		if _, err := tx.Exec(ctx, "UPDATE authz_record SET disposition = $2 WHERE id = $1", id, disp); err != nil {' "the replaced holding is not held"
mut $V '		AND (d.origin = '"'"'identity_side'"'"' OR d.disposer IN' '		AND (false OR d.disposer IN' "identity-side dispositions are not released"
mut $V '		entered_from = NULL, recovery_identity = NULL, admin_state_since = now() WHERE admin_state = '"'"'admin_recovery'"'"'`)' '		entered_from = NULL, recovery_identity = NULL, admin_state_since = now() WHERE false`)' "abort does nothing"
mut $P '	if err != nil || a.now != proven {' '	if err != nil || false {' "operational with the account not active"
echo "done" >> "$out"
