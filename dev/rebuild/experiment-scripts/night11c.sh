#!/bin/bash
# Step 11, the checks night11 did not have (11-01 section 4; be-acceptance v1.0.12): the D and K rows' S, H and X
# cells under the background load again, with the faults whose aftermath the new invariants judge (the department
# projection, the audit trail, every published event in its stream) and RS18 now timing the outbox backlog and the
# projection catching up: R1 and R2, then R5 on H and X. R3 (a burst of billing, a latency question) and R4 (an
# upgrade, which needs a new release) are left out. LD9-S is the local process crash instead (local11.sh). About an
# hour a cell, 15 minutes for LD9-S; run in rounds of a few cells when the machine is free, into one <out>, each
# round under its own subdirectory (<out>/<round>), the cells in the order given; a row's cells run as one batch.
# Usage: night11c.sh <out> <round> <cell>...   (CONF: a snapshot of the conformance tools; under night-wrap.sh)
set -u
OUT=$(realpath -m "$1"); ROUND=$2; shift 2; X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT/$ROUND"; echo $$ > "$OUT/$ROUND/night.pid"; LOG=$OUT/$ROUND/night.log
export FAULTS='rs06,rs05,bl04,process_crashes and sales,process_crashes and inventory,process_crashes and billing,rs18,authorization,database,split'
echo "NIGHT START $ROUND $* $(date -Is) brickkit=$(brickkit --version | head -1)" >> "$LOG"
D=(); K=(); LD=
for c in "$@"; do case $c in D*) D+=("$c") ;; K*) K+=("$c") ;; LD9-S) LD=1 ;; *) echo "unknown cell $c" >&2; exit 2 ;; esac; done
[ ${#D[@]} -gt 0 ] && { "$X/runner11.sh" "$OUT/$ROUND/d" "${D[@]}"; echo "NIGHT d done exit=$? $(date -Is)" >> "$LOG"; }
[ ${#K[@]} -gt 0 ] && { "$X/runner11.sh" "$OUT/$ROUND/k" "${K[@]}"; echo "NIGHT k done exit=$? $(date -Is)" >> "$LOG"; }
[ -n "$LD" ] && { "$X/local11.sh" "$OUT/$ROUND/ld"; echo "NIGHT ld done exit=$? $(date -Is)" >> "$LOG"; }
echo "NIGHT ALL-DONE $(date -Is)" >> "$LOG"
