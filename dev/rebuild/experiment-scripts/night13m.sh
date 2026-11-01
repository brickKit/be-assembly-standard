#!/bin/bash
# Step 13, step 7 (step13-plan.md): E5 and E6's cost. Three cells measured as step 9 measured the trading chain
# (runner9.sh: empty idle; then seed data, baseline, the expectation and scope scenarios, the result digest compared
# with the pass's first cell, idle, warmup and the 7/s mix): D13-E6a (one database, a schema per component: the
# reference), D13-E5 (the trading components on a second PostgreSQL instance), D13-E6b (a database per component).
# One batch in two passes, the order ABC then CBA so that a drift over the night falls on both sides; two readings of each give the
# spread. Shorter windows than step 9 (idle 300 s, warmup 180 s, mix 600 s) to fit the night: about 5 hours.
# Usage: night13m.sh <out>   (CONF: a snapshot of the conformance tools; run it under night-wrap.sh)
set -u
OUT=$(realpath -m "$1"); X=$(dirname "$(realpath "$0")")
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT13M START $(date -Is)" >> "$OUT/night.log"
# one runner9.sh per pass: it keeps a cell's outputs under the cell's name, so a cell twice in one call would overwrite
IDLE=300 WARMUP=180 SECONDS_=600 "$X/runner9.sh" "$OUT/p1" D13-E6a D13-E5 D13-E6b
echo "NIGHT13M pass 1 exit=$? $(date -Is)" >> "$OUT/night.log"
IDLE=300 WARMUP=180 SECONDS_=600 "$X/runner9.sh" "$OUT/p2" D13-E6b D13-E5 D13-E6a
echo "NIGHT13M pass 2 exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT13M ALL-DONE $(date -Is)" >> "$OUT/night.log"
