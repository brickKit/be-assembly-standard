#!/usr/bin/env bash
# Mutation runs for infra/authz's confirmation records (T5a: confirmation records): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.18 in progress (T5a confirmations), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
C=authz/confirm.go
mut $C '	if err != nil || !admin {
		return disproven, err' '	if err != nil || false && !admin {
		return disproven, err' "anyone with the change permission confirms (A123)"
mut $C '				consumed_by_change IS NULL AND expires_at > now() FROM' '				consumed_by_change IS NULL FROM' "an expired confirmation holds"
mut $C '		if !c.Live || c.Target != t.ID || c.Revision == nil' '		if !c.Live || c.Revision == nil' "a confirmation for another record holds"
mut $C '|| *c.Revision != t.Revision || c.Confirmer == requester ||' '|| c.Confirmer == requester ||' "a confirmation for another revision holds"
mut $C '|| *c.Revision != t.Revision || c.Confirmer == requester ||' '|| *c.Revision != t.Revision ||' "the requester's own confirmation holds"
mut $C '			c.Confirmer == object {' '			false && c.Confirmer == object {' "the object's own confirmation holds"
mut $C '		case ok == disproven:
			f.Confirmation = confirmInvalid' '		case ok == disproven:
			f.Confirmation = confirmValid' "a confirmer no longer eligible still counts"
mut $C '	_, err := tx.Exec(ctx, "UPDATE authz_confirmation SET consumed_by_change = $2 WHERE id::text = ANY($1)", list, change)' '	_, err := tx.Exec(ctx, "SELECT $1::text[], $2::text", list, change)' "a confirmation is never marked used"
mut $C '				consumed_by_change IS NULL AND expires_at > now() FROM' '				expires_at > now() FROM' "a used confirmation holds again"
echo "done" >> "$out"
