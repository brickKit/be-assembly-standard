#!/bin/bash
# Step 13's night of 2026-11-01 (the maintainer: steps 4 to 7 in one go, the machine quiet after midnight). Waits for
# step 4 (step4-13.sh) to finish, then:
#   step 5, E3: on the replicated cells a replica stopped and crashed under load (faults -k "e3 and <component>"),
#     then RS06 and RS05 (an in-flight confirmation's coordinator crashes) with replicas; the D row, then the K row;
#   step 6, E7: the business database rolled back to T on D13-E7, once as it is and once with the audit component
#     paused for the last 120 s before the freeze (a loss that is not zero);
#   step 7, E5 and E6's cost: night13m.sh under night-wrap.sh (performance power mode, a snapshot of the tools).
# The power mode is balanced for steps 5 and 6 (correctness) and performance only for step 7. night.log gets the
# outermost mark NIGHT13 ALL-DONE. Usage: night13.sh <out> <step4 out>
set -u
OUT=$(realpath -m "$1"); S4=$(realpath -m "$2"); X=$(dirname "$(realpath "$0")"); R=$(realpath "$X/../../..")
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"; LOG=$OUT/night.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
say "NIGHT13 START waiting for step 4"
until grep -q 'STEP4 ALL-DONE' "$S4/step4.log" 2>/dev/null; do sleep 30; done
say "NIGHT13 step 4 done: $(tail -2 "$S4/step4.log" | head -1)"
E3_1='faults:e3 and sales,faults:e3 and inventory,faults:rs06,faults:rs05'
E3_2='faults:e3 and sales,faults:rs06,faults:rs05'  # one shell hosts sales and inventory: one replica to stop
STEPS=$E3_1 "$X/runner13.sh" "$OUT/s5-d-e1" D13-E1; say "NIGHT13 step 5 D13-E1 exit=$?"
STEPS=$E3_2 "$X/runner13.sh" "$OUT/s5-d-e2" D13-E2; say "NIGHT13 step 5 D13-E2 exit=$?"
KEEP_CLUSTER=1 STEPS=$E3_1 "$X/runner13.sh" "$OUT/s5-k-e1" K13-E1; say "NIGHT13 step 5 K13-E1 exit=$?"
STEPS=$E3_2 "$X/runner13.sh" "$OUT/s5-k-e2" K13-E2; say "NIGHT13 step 5 K13-E2 exit=$?"
E7_AFTER=300 STEPS=e7 "$X/runner13.sh" "$OUT/s6-e7" D13-E7; say "NIGHT13 step 6 D13-E7 exit=$?"
E7_AFTER=300 E7_PAUSE=120 STEPS=e7 "$X/runner13.sh" "$OUT/s6-e7-pause" D13-E7; say "NIGHT13 step 6 D13-E7 paused audit exit=$?"
SNAP=$OUT/conf-snapshot
rsync -a --exclude .git --exclude .venv --exclude __pycache__ "$R/tools/be-acceptance/" "$SNAP/" && (cd "$SNAP/conformance" && uv sync -q) \
  && say "NIGHT13 snapshot of the tools at $(git -C "$R/tools/be-acceptance" describe --tags)" || say "NIGHT13 FAILED snapshot"
CONF=$SNAP/conformance "$X/night-wrap.sh" "$OUT/s7-wrap" "$X/night13m.sh" "$OUT/s7"; say "NIGHT13 step 7 exit=$?"
say "NIGHT13 ALL-DONE"
