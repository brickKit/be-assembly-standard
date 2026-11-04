#!/bin/bash
# P9.34 mutants of be-protocol's reference recomputation (run from tools/be-protocol)
m() { local name=$1 from=$2 to=$3; cp watermark_test.go /tmp/wt.bak
  grep -qF -- "$from" watermark_test.go || { echo "MISSING $name"; return; }
  python3 -c "import sys,pathlib;p=pathlib.Path('watermark_test.go');s=p.read_text();p.write_text(s.replace(sys.argv[1],sys.argv[2],1))" "$from" "$to"
  if go test -run TestWatermarkJudgeVectors . >/tmp/wt.out 2>&1; then echo "SURVIVED $name"; else echo "KILLED $name | $(grep -m1 'vector says' /tmp/wt.out)"; fi
  cp /tmp/wt.bak watermark_test.go; }
m "age counts under last_applied" 'fresh := applied ||' 'fresh := false ||'
m "stalled refused under last_applied" 'applied && q.SourceState == "stalled"' 'false && q.SourceState == "stalled"'
m "blocked accepted under last_applied" 'applied && q.SourceState == "stalled"' 'applied && q.SourceState != "aligning"'
