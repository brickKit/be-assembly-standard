#!/bin/bash
# FRB-009 retest, item 3: test/probe-py in mode: debug with localPort 9999 (deploy.local.yaml); up --dry-run only.
set -u
S=$(cd "$(dirname "$0")" && pwd); C=${TMPDIR:-/tmp}/frb009-debug
R=/home/zhijie/Desktop/github/be-assembly-standard
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }  # secrets read at run time
export BE_ACC_NATS_URL=nats://localhost:4222 BE_ACC_S3_URL=http://localhost:9000
export BE_ACC_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY; BE_ACC_S3_ACCESS_KEY=$(envval STORAGE_ACCESS_KEY); BE_ACC_S3_SECRET_KEY=$(envval STORAGE_SECRET_KEY)
rm -rf "$C"; cp -a "$R/dev/rebuild/experiment-cells/D9-probe-pyonly" "$C"; cd "$C"
brickkit local on >/dev/null 2>&1 || exit 1
python3 - <<'PY'
import re
t = open('deploy.local.yaml').read()
open('deploy.local.yaml', 'w').write(re.sub(r"(  - id: test/probe-py\n)", r"\1    mode: debug\n    localPort: 9999\n", t, count=1))
PY
brickkit up --dry-run >/dev/null 2>&1; echo "dry-run exit=$?"
ls .brickkit/generated/local-debug.*.env
grep -h '^PORT=' .brickkit/generated/local-debug.*.env
grep -n 'PROBE_NEXT_URL=.*9999\|test-probe-py-3-2-19:host-gateway' .brickkit/generated/compose.yaml
rm -rf "$C"
