#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.23 in progress (T8b): each rule broken by one edit; the unit tests, or for the
# security event the integration tests too; the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.23 in progress (T8b), $(date -I): each rule broken by one edit; go test ./authz/ (unit), and go test -tags integration ./authz/ for the security event; the file restored; a crash counts as red." >> "$out"
mut() { tags=$1; f=$2; old=$3; new=$4; label=$5; cp "$f" /tmp/claude-1000/ma.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/ma.bak "$f"; return; fi
  r=$(go test -count=1 $tags ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/ma.bak "$f"; }
V=authz/view.go; EF=authz/effective.go; SB=authz/submit.go
mut "" $V '	return mine && d.operations[s.Operation] && reg.usable(s.Operation) && s.Check(r) == nil' '	return mine && d.operations[s.Operation] && reg.usable(s.Operation) && r != nil' "a segment missing a dimension enters the view (FX01)"
mut "" $EF '		return y, atomNonEmpty(y)' '		return y, true' "all with an empty atom is not empty (FX03)"
mut "" $EF '		return x, atomNonEmpty(x)' '		return x, true' "an empty atom with all is not empty (FX03)"
mut "" $EF '		return len(a.Values) > 0' '		return true' "an explicit empty set is not empty (FX03)"
mut "" $EF '		return len(a.Items) > 0' '		return true' "an empty tree is not empty (FX03)"
mut "" $EF '	case "interval":
		return nonEmpty(a)
	}' '	case "interval":
		return true
	}' "an empty interval is not empty (FX03)"
mut "" $SB '			if f, _ := cat["field"].(string); fields[f] == nil {' '			if f, _ := cat["field"].(string); false && fields[f] == nil {' "an attachment category on no field passes (EN22)"
mut "" $SB '		if body["purpose"] != "manage" || len(effects) != 1 || effects[0] != "security_change" {' '		if len(effects) != 1 || effects[0] != "security_change" {' "tightening only on a non-manage operation passes (EN24)"
mut "" $SB '	if body["authority"] != component {' '	if false && body["authority"] != component {' "another component as the authority passes (EN21)"
mut "-tags integration" $SB '		m.ownerMismatch(ctx, in.GetComponent(), in.GetVersion(), bad)' '' "an owner mismatch is not a security event (EN21, EN23)"
mut "-tags integration" $SB '		if r.reason == "DEFINITION_OWNER_MISMATCH" {' '		if r.reason == "DEFINITION_INVALID" {' "the security event is for the wrong rejections"
echo "done" >> "$out"
