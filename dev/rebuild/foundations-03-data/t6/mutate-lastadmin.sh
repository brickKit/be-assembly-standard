#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6d: the last-admin invariant by the holdings a change ends): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6d), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
Q=authz/requester.go
mut $Q '		AND record_type = '"'"'management_holding'"'"' AND body->>'"'"'system_role'"'"' = '"'"'authorization_admin'"'"' AND id::text <> ALL($1)`,' '		AND record_type = '"'"'management_holding'"'"' AND body->>'"'"'system_role'"'"' = '"'"'authorization_admin'"'"' AND body->>'"'"'holder'"'"' NOT IN (SELECT body->>'"'"'holder'"'"' FROM authz_record WHERE id::text = ANY($1))`,' "the person is gone with one holding"
mut $Q '	case "management_unit":
		recs, err := active(ctx, tx, "management_holding")' '	case "management_unit_":
		recs, err := active(ctx, tx, "management_holding")' "ending a unit ends no admin holding"
mut $Q '	if err != nil || len(holders) == 0 {
		return disproven, err
	}' '	if err != nil || len(holders) == 0 {
		return proven, err
	}' "no admin left is fine"
echo "done" >> "$out"
