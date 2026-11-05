#!/usr/bin/env bash
# Mutation runs for be-sdk-python 3.0.0a49 in progress (T8a): each rule broken by one edit, the affected unit and
# integration tests run (the protocol copy holds the local be-protocol's vectors), the file restored. Run from
# tools/be-sdk-python with itenv.sh sourced.
out=$1; : > "$out"
# the bytecode cache off and cleared before each mutant: an equal-length edit written within the same second would
# otherwise run the previous version's .pyc (foundations item 3, T5e)
export PYTHONDONTWRITEBYTECODE=1
echo "be-sdk-python 3.0.0a49 in progress (T8a, second round: the mutant that was red on a crash, rewritten to accept an undeclared dimension), $(date -I): each rule broken by one edit; uv run pytest tests/test_authz.py tests/test_records.py tests/test_security.py and -m integration tests/test_authz_sql_integration.py tests/test_lists_integration.py; the file restored; bytecode cache off and cleared before each mutant." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/mp.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  find besdk tests -name __pycache__ -type d -prune -exec rm -rf {} +
  r=$( { uv run pytest -q -p no:cacheprovider tests/test_authz.py tests/test_records.py tests/test_security.py 2>&1; uv run pytest -q -p no:cacheprovider -m integration tests/test_authz_sql_integration.py tests/test_lists_integration.py 2>&1; } )
  if echo "$r" | grep -q "failed\|error"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "^FAILED|^ERROR" | head -3 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/mp.bak "$f"; }
E=besdk/authz/segment.py; S=besdk/authz/subject.py; V=besdk/authz/view.py; HO=besdk/host.py; P=besdk/authz/plan.py; L=besdk/lists.py; RC=besdk/records.py
mut $E '            d = dims.get(dim)' '            d = dims.get(dim) or next(iter(dims.values()))' "an undeclared dimension passes (EN08)"
echo "done" >> "$out"
