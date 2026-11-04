#!/usr/bin/env bash
# Mutation runs for infra/authz 3.0.20 (T6a: security dispositions, A128): each rule broken by one edit, the unit and integration tests run (go test -tags integration runs
# both), the file restored. Run from components/infra/authz with AUTHZ_IT_PG_PASSWORD set.
out=$1; : > "$out"
echo "infra/authz 3.0.20 in progress (T6a), $(date -I): each rule broken by one edit, go test -tags integration ./authz/, the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
V=authz/view.go; D=authz/disposition.go; F=authz/facts.go; E=authz/enact.go; G=authz/change.go
mut $V '			if !defs.usable(s, reg) || suspended(disposed[b.Grantee], s, b.Grantee) {' '			if !defs.usable(s, reg) {' "a grant's segments are not suspended"
mut $V '				if !defs.usable(s, reg) || suspended(disposed[p], s, p) {' '				if !defs.usable(s, reg) {' "the fixed segments are not suspended"
mut $D '		return !slices.ContainsFunc(x.Values, func(v string) bool { return slices.Contains(y.Values, v) })' '		return false' "value sets never disjoint"
mut $D '		return !slices.ContainsFunc(x.Values, func(v string) bool { return slices.Contains(y.Values, v) })' '		return true' "value sets always disjoint"
mut $D '			if b.Grantee != in.Subject || !under(b.GovernanceUnit) {' '			if b.Grantee != in.Subject {' "grants above the domain are held"
mut $D '			if slices.ContainsFunc(segs, func(sg sdkauthz.Segment) bool { return suspended(scope, sg, in.Subject) }) {' '			if false {' "no grant is held"
mut $D '			if h.Holder == in.Subject && under(h.Unit) {' '			if false {' "no management holding is held"
mut $D '		f.AffectsAdmins, f.TightenNeedsConfirmation = true, in.Subject != e.requester' '		f.AffectsAdmins, f.TightenNeedsConfirmation = true, false' "disposing another admin is not protected"
mut $D '		if why != "" {
			return false, &changeResult{Outcome: "rejected", Reason: errs.ReasonContainmentNotProven, Detail: why}, nil
		}' '		_ = why' "the scope need not be within the limit"
mut $D '	case in.All && !sameUnit(s.units, domain, root):' '	case false:' "every segment from any domain"
mut $D '	return s.manages(domain), nil, nil' '	return true, nil, nil' "anyone disposes"
mut $F '		if relinquish && t.HoldReason == "security_hold" {' '		if false {' "the disposed person gives up what is held (CP110)"
mut $F '	case t == nil || t.Type != p.recType || t.State != "active" && !disposed:' '	case t == nil || t.Type != p.recType || t.State != "active":' "a held grant cannot be renewed (CP31)"
mut $E '	if p.successor != "" && !p.keepPredecessor && (p.activate || p.target == nil) {' '	if p.successor != "" && (p.activate || p.target == nil) {' "the renewal ends the held predecessor"
mut $G '	case isDisposition(e.req.Candidate):
		return OpDispose' '	case false:
		return OpDispose' "the audit names the tightening operation"
echo "done" >> "$out"
