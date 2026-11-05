#!/bin/bash
# K1 mutation check of P9.35 in be-sdk-go alpha.84: each mutant must turn TestAWatermarkNoOlderThanAMoment red.
set -u
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-go
. /tmp/claude-1000/mt/allenv.sh
out=$(dirname "$0")
mut() { # name file old new
  local name=$1 f=$2 old=$3 new=$4
  cp "$f" "$f.orig"
  python3 - "$f" "$old" "$new" <<'PY' || { mv "$f.orig" "$f"; echo "$name: NOT APPLIED"; return; }
import sys
p,o,n=sys.argv[1:]
s=open(p).read()
assert s.count(o)==1, "pattern count %d" % s.count(o)
open(p,'w').write(s.replace(o,n))
PY
  timeout 250 go test -tags integration -count=1 -run TestAWatermarkNoOlderThanAMoment ./projection/ >"$out/$name.log" 2>&1
  local rc=$?
  mv "$f.orig" "$f"
  if [ $rc -eq 0 ]; then echo "$name: SURVIVED"; else echo "$name: killed ($(grep -m1 -E 'Error:|Messages:|undefined' "$out/$name.log" | sed 's/^ *//'))"; fi
}
mut m1-no-flag projection/watermark.go '	w.soon.Store(true)' '	_ = 0'
mut m2-no-moment projection/watermark.go 'p.echo_mp IS NOT NULL AND p.echo_mp >= $3)' 'p.echo_mp IS NOT NULL AND $3::timestamptz IS NOT NULL)'
mut m3-null-echo projection/watermark.go 'p.echo_mp IS NOT NULL AND p.echo_mp >= $3)' 'coalesce(p.echo_mp >= $3, true))'
mut m4-any-status projection/watermark.go 'bool_and(ps.status = $2 AND' 'bool_and($2::text IS NOT NULL AND'
echo "MUTANTS DONE"
