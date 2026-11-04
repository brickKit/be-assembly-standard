#!/bin/bash
# P9.34 mutants of be-sdk-go's Judge and JudgeApplied (run from tools/be-sdk-go with itenv.sh sourced)
m() { local name=$1 file=$2 from=$3 to=$4; cp "$file" /tmp/mut.bak
  grep -qF -- "$from" "$file" || { echo "MISSING $name"; return; }
  python3 -c "import sys,pathlib;p=pathlib.Path(sys.argv[1]);s=p.read_text();p.write_text(s.replace(sys.argv[2],sys.argv[3],1))" "$file" "$from" "$to"
  if go test -tags integration -p 1 ./projection/ -run 'Rollback|Quarantines|TwoFreshnesses|Vectors' >/tmp/mut.out 2>&1; then echo "SURVIVED $name"
  else echo "KILLED $name | $(grep -m1 -E 'Error:|--- FAIL' /tmp/mut.out | tr -s ' \t' ' ')"; fi
  cp /tmp/mut.bak "$file"; }
m "stalled refused" projection/decide.go '!(q.LastApplied && q.SourceState == Stalled)' '!(false && q.SourceState == Stalled)'
m "any state accepted" projection/decide.go 'q.SourceState != Aligned && !(q.LastApplied && q.SourceState == Stalled), ' 'false, '
m "age counts" projection/decide.go 'case !q.LastApplied && (' 'case true && ('
m "applied ignored in JudgeApplied" projection/watermark.go 'return w.judgeMany(ctx, tx, asked, 0, true)' 'return w.judgeMany(ctx, tx, asked, 0, false)'
m "source state not reported" projection/watermark.go 'Source: Unprovable, SourceState: status,' 'Source: Unprovable,'
m "quarantine ignored when applied" projection/decide.go '		q.Quarantined:' '		q.Quarantined && !q.LastApplied:'
