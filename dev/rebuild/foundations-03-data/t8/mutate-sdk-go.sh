#!/usr/bin/env bash
# Mutation runs for be-sdk-go alpha.71 in progress (T8a): each rule broken by one edit, the packages' unit and
# integration tests run against the local be-protocol (GOWORK), the file restored. Run from tools/be-sdk-go with
# itenv.sh sourced and GOWORK set.
out=$1; : > "$out"
echo "be-sdk-go alpha.71 in progress (T8a), $(date -I): each rule broken by one edit; go test -tags integration -p 1 ./authz/ ./list/ ./records/ ./launcher/ (launcher: TestOthersSeeNothingAndFieldsFollowTheSegments only); the file restored; a crash counts as red." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz ./list ./records ./launcher >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$( { go test -count=1 -tags integration -p 1 ./authz/ ./list/ ./records/ 2>&1; go test -count=1 -tags integration ./launcher/ -run TestOthersSeeNothingAndFieldsFollowTheSegments 2>&1; } )
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
E=authz/eval.go; S=authz/subject.go; G=authz/segment.go; RF=authz/refuse.go; Q=authz/sql.go; L=list/list.go; RC=records/records.go; H=internal/host/build.go
mut $E '		act, fields = entitled(segs, op, facts, principal, at)' '		act, _ = entitled(segs, op, facts, principal, at)' "an operation's fields are the view's (AE08)"
mut $S '			shaped[k] = nil
			masked = append(masked, k)' '			masked = append(masked, k)' "a masked field is dropped, not null (AE04)"
mut $S '	if len(masked) > 0 {' '	if true {' "_masked present when nothing is masked"
mut $S '		case !declared || fd.Class == Secret:' '		case !declared:' "a secret field is masked instead of dropped"
mut $S '			masked = append(masked, k)
		}
	}' '		}
	}' "_masked does not name the masked fields"
mut $RF '			if err := s.Check(r); err != nil {' '			if err := s.Check(r); err != nil && false {' "a segment that does not fit is kept (FX01)"
mut $RF '	if defs == nil {' '	if true {' "the holder never checks segments"
mut $H '	m.holder.Defs = m.Def.Authz' '' "the launcher does not give the holder its definitions"
mut $G '	if len(s.Atoms) != len(r.Dimensions) {' '	if false {' "a segment missing a dimension passes the check (EN08)"
mut $G '		if !ok {
			return fmt.Errorf("segment for %s: dimension %s is not declared", s.Operation, dim)' '		if !ok && false {
			return fmt.Errorf("segment for %s: dimension %s is not declared", s.Operation, dim)' "an undeclared dimension passes (EN08)"
mut $G '		if !readable[f] {' '		if false {' "a written field need not be readable (EN09)"
mut $G '(a.Lo != nil) != (a.LoClosed != nil) || (a.Hi != nil) != (a.HiClosed != nil)' 'false' "an interval end without its closed flag passes (EN10)"
mut $RC '			if name, _ := f.(string); !knownFeatures[name] {' '			if name, _ := f.(string); false && !knownFeatures[name] {' "an unknown required feature is ignored (EN05)"
mut $Q '		if slices.Contains(set, field) {' '		if true {' "readable_only keeps rows that do not show the field (FX12)"
mut $L '			where = append(where, plan.ReadableWhere(f))' '' "readable_only does not narrow"
mut $L '		return res != nil && res.Fields[field].Class != authz.Ordinary && !narrowed[field]' '		return res != nil && res.Fields[field].Class != authz.Ordinary' "a narrowed field still cannot sort or filter"
mut $L ', "readable_only": q.ReadableOnly})' '})' "the narrowing is not in the filter digest"
echo "done" >> "$out"
