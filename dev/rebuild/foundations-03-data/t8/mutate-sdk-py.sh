#!/usr/bin/env bash
# Mutation runs for be-sdk-python 3.0.0a49 in progress (T8a): each rule broken by one edit, the affected unit and
# integration tests run (the protocol copy holds the local be-protocol's vectors), the file restored. Run from
# tools/be-sdk-python with itenv.sh sourced.
out=$1; : > "$out"
# the bytecode cache off and cleared before each mutant: an equal-length edit written within the same second would
# otherwise run the previous version's .pyc (foundations item 3, T5e)
export PYTHONDONTWRITEBYTECODE=1
echo "be-sdk-python 3.0.0a49 in progress (T8a), $(date -I): each rule broken by one edit; uv run pytest tests/test_authz.py tests/test_records.py tests/test_security.py and -m integration tests/test_authz_sql_integration.py tests/test_lists_integration.py; the file restored; bytecode cache off and cleared before each mutant." >> "$out"
mut() { f=$1; old=$2; new=$3; label=$4; cp "$f" /tmp/claude-1000/mp.bak
  python3 -c "import sys;p,o,n=sys.argv[1:];s=open(p).read();assert s.count(o)==1,o;open(p,'w').write(s.replace(o,n))" "$f" "$old" "$new" || { echo "PATTERN MISSING: $label" >> "$out"; return; }
  find besdk tests -name __pycache__ -type d -prune -exec rm -rf {} +
  r=$( { uv run pytest -q -p no:cacheprovider tests/test_authz.py tests/test_records.py tests/test_security.py 2>&1; uv run pytest -q -p no:cacheprovider -m integration tests/test_authz_sql_integration.py tests/test_lists_integration.py 2>&1; } )
  if echo "$r" | grep -q "failed\|error"; then echo "red  $label" >> "$out"; echo "$r" | grep -E "^FAILED|^ERROR" | head -3 | cut -c1-200 | sed 's/^/       /' >> "$out"
  else echo "GREEN (survived)  $label" >> "$out"; fi
  cp /tmp/claude-1000/mp.bak "$f"; }
E=besdk/authz/segment.py; S=besdk/authz/subject.py; V=besdk/authz/view.py; HO=besdk/host.py; P=besdk/authz/plan.py; L=besdk/lists.py; RC=besdk/records.py
mut $E '        act, fields = _entitled(segs, op, facts, principal, at)' '        act, _ = _entitled(segs, op, facts, principal, at)' "an operation's fields are the view's (AE08)"
mut $S '            shaped[k] = None
            masked.append(k)' '            masked.append(k)' "a masked field is dropped, not None (AE04)"
mut $S '    if masked:' '    if True:' "_masked present when nothing is masked"
mut $S '        if fd is None or fd.cls == SECRET:' '        if fd is None:' "a secret field is masked instead of dropped"
mut $S '        shaped[MASKED] = sorted(masked)' '        shaped[MASKED] = []' "_masked does not name the masked fields"
mut $V '                        s.check(r)' '                        pass' "a segment that does not fit is kept (FX01)"
mut $V '        if self.defs is None:' '        if True:' "the holder never checks segments"
mut $HO ', member.logger, defs=d.authz)' ', member.logger)' "the host does not give the holder its definitions"
mut $E '        if len(self.atoms) != len(dims):' '        if False:' "a segment missing a dimension passes the check (EN08)"
mut $E '            if d is None:
                raise' '            if d is None and False:
                raise' "an undeclared dimension passes (EN08)"
mut $E '        if unreadable := set(self.write_fields) - set(self.read_fields):' '        if unreadable := set():' "a written field need not be readable (EN09)"
mut $E 'or (a.lo is None) != (a.lo_closed is None) or (a.hi is None) != (a.hi_closed is None)' '' "an interval end without its closed flag passes (EN10)"
mut $RC '        if f not in KNOWN_FEATURES:' '        if False:' "an unknown required feature is ignored (EN05)"
mut $P '        ors = [self.hits[i] for i, s in enumerate(self.sets) if name in s]' '        ors = list(self.hits)' "readable_only keeps rows that do not show the field (FX12)"
mut $L '            where.append(plan.readable_where(name))' '            pass' "readable_only does not narrow"
mut $L ' and name not in narrowed' '' "a narrowed field still cannot sort or filter"
mut $L ',
                           "readable_only": narrowed})' '})' "the narrowing is not in the filter digest"
echo "done" >> "$out"
