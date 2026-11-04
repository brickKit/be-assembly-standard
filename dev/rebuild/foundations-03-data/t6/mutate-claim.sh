#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6g: the install claim, A130): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6g), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
C=authz/claim.go
mut $C '		if kind == "principal" && value != u.Subject || kind == "code" && (in.Code == "" || hex.EncodeToString(sum[:]) != value) {' '		if kind == "code" && (in.Code == "" || hex.EncodeToString(sum[:]) != value) {' "anyone claims a principal's claim"
mut $C '		if errors.Is(err, pgx.ErrNoRows) || err == nil && !open {
			return refused
		}' '		if errors.Is(err, pgx.ErrNoRows) {
			return refused
		}' "a consumed claim is open (the holdings check stays)"
mut $C '		if holdings > 0 {
			return refused
		}' '' "management already there (the consumed check stays)"
echo "done" >> "$out"
