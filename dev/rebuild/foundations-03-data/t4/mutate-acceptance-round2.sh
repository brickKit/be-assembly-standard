#!/usr/bin/env bash
# Mutation runs for infra/authz's closure job and dependency index (T4 acceptance: the cases added for CP81, CP91, CP98): each rule broken by one edit, the unit and integration
# tests run (go test -tags integration runs both), the file restored. Run from components/infra/authz with
# AUTHZ_IT_PG_PASSWORD set.
out=$1
echo "round 2, $(date -I): the third mutant with its pattern as formatted (gofmt split the line)." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/m.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  if ! go vet -tags integration ./authz >/dev/null 2>&1; then echo "does not compile: $label" >> "$out"; cp /tmp/claude-1000/m.bak "$f"; return; fi
  r=$(go test -count=1 -tags integration ./authz/ 2>&1)
  if echo "$r" | grep -q -- "^FAIL\|--- FAIL"; then echo "red  $label" >> "$out"; echo "$r" | grep -E -- "--- FAIL|Error:|Messages:" | grep -v '"level"' | head -4 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/m.bak "$f"; }
mut authz/scheduled.go '	return a.Record + ":" + strconv.FormatInt(a.StateRevision, 10) + ":" + a.Trigger' '	return a.Record + ":" + a.Trigger + strconv.FormatInt(0*a.StateRevision, 10)' "the derived key has no state revision (CP81)"
echo "done" >> "$out"
