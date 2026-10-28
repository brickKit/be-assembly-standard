#!/bin/bash
# The night of 2026-10-28 (step9-plan.md 8.7, step10-plan.md 5.1), two batches one after the other, each compared only
# within itself: the step 9 probes on every row (night9c.sh, about 5.5 hours), then step 10's B1 and B2 with their
# references (runner9.sh: the business chain, the same flow and parameters as step 9; about 5.5 hours): D9-S, D9-S-pgb
# (B1, PgBouncer), D9-S-pgq (B2, PostgreSQL queue), D9-X, D9-X-pgq, D9-H.
# Usage: night10a.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
"$X/night9c.sh" "$OUT/step9"; echo "NIGHT step9 probes done exit=$? $(date -Is)" >> "$OUT/night.log"
"$X/runner9.sh" "$OUT/b12" D9-S D9-S-pgb D9-S-pgq D9-X D9-X-pgq D9-H
echo "NIGHT b12 done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
