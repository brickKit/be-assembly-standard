#!/bin/bash
# Step 13, step 4 (step13-plan.md): E1, E2 and E4's correctness under the background load, one runner13.sh per group
# of cells with the same steps: the replicated cells run the L3 scenarios twice under the load (RS01, RS08 at once,
# RS16 among them), the E4 cell the out-of-order injection before and after a round of scenarios; every step is
# followed by the invariants, and each cell's work holders and per-replica counts are kept. The D row first, the K
# row last (runner13.sh starts and stops the cluster). step4.log gets the outermost mark STEP4 ALL-DONE.
# Usage: step4-13.sh <out>
set -u
OUT=$(realpath -m "$1"); X=$(dirname "$(realpath "$0")")
mkdir -p "$OUT"; echo $$ > "$OUT/step4.pid"; LOG=$OUT/step4.log
say() { echo "$* $(date -Is)" >> "$LOG"; }
say "STEP4 START"
STEPS=scenarios,scenarios "$X/runner13.sh" "$OUT/e1e2-d" D13-E1 D13-E2; say "STEP4 e1e2-d exit=$?"
STEPS=e4,scenarios,e4 "$X/runner13.sh" "$OUT/e4" D13-E4; say "STEP4 e4 exit=$?"
STEPS=scenarios,scenarios "$X/runner13.sh" "$OUT/e1e2-k" K13-E1 K13-E2; say "STEP4 e1e2-k exit=$?"
say "STEP4 $(grep -h -c 'FAILED\|VIOLATED' "$OUT"/*/status.log | paste -sd+ | bc) failures or violations"
say "STEP4 ALL-DONE"
