#!/usr/bin/env bash
# Mutation runs for the probes 3.2.38 in progress (T8c): each rule of the entries broken by one edit, the suite's
# authorization profile run against that probe, the file restored. Run from tools/be-acceptance with the suite's
# environment (BE_ACC_*) set.
out=$1; : > "$out"
export PYTHONDONTWRITEBYTECODE=1  # see mutate-sdk-py.sh
echo "probes 3.2.38 in progress (T8c, the Python mutants again with the bytecode cache off and cleared), $(date -I): each rule broken by one edit; uv run pytest conformance/tests/test_authz_profile.py::...[go|py]; the file restored; red = the profile's verdict is not 符合." >> "$out"
mut() { kind=$1; f=$2; old=$3; new=$4; label=$5; cp "$f" /tmp/claude-1000/mpr.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  find probes/py -name __pycache__ -type d -prune -exec rm -rf {} +
  r=$(cd conformance && timeout 600 uv run pytest -q -s "tests/test_authz_profile.py::test_the_probes_conform_to_the_authorization_profile[$kind]" 2>&1)
  if echo "$r" | grep -q " passed"; then echo "GREEN (survived)  $kind: $label" >> "$out"
  else echo "red  $kind: $label" >> "$out"; echo "$r" | grep -E "^  CK-AZ.* (失败|检查失效)|exited|^E   .*Error" | head -3 | cut -c1-220 | sed 's/^/       /' >> "$out"; fi
  cp /tmp/claude-1000/mpr.bak "$f"; }
G=probes/go/probe/entries.go; P=probes/py/probe_py/entries.py
mut py $P '    try:
        authz.subject().check(op, facts(e))
    except errs.Error as err:' '    try:
        return
    except errs.Error as err:' "a command's target state is not checked (AE15)"
mut py $P '        out = {"items": [authz.mask(self.res, e, q.fields(hits)) for e, hits in rows],' '        out = {"items": [authz.mask(self.res, e, list(self.res.fields)) for e, hits in rows],' "the list shows every field, not the hit segments' (P8.17)"
mut py $P '        return await self.one(c, EXPORT)' '        return await self.one(c, READ)' "the export outputs the page's fields (P8.15)"
echo "done" >> "$out"
