#!/bin/bash
# Step 10, B3 and B4 (step10-plan.md 4.1): the whole stack under a memory budget, one batch. Every Docker container
# (the cells and the base resources) is in be-cap.slice (cap/setup.sh, run once by the maintainer); runner9.sh sets the
# slice's limit per cell (cell.yaml memory_cap), samples it (cap.tsv) and records the containers' states before each
# down (containers.txt). References first, without a limit, then 6 GiB, then 4 GiB (a cell that breaks does not stop
# the rest): D9-H, D9-S, D9-H-m6, D9-S-m6, D9-H-m4, D9-S-m4. Same flow and load as step 9. About 5.5 hours.
# Usage: night10c.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
# the setup has to be in place: the base resources in the slice, the limit settable without a password
pg=$(cat /proc/"$(docker inspect be-postgres --format '{{.State.Pid}}')"/cgroup)
case $pg in *be-cap.slice*) ;; *) echo "NIGHT ABORT be-postgres not in be-cap.slice ($pg): run cap/setup.sh" >> "$OUT/night.log"; exit 1 ;; esac
"$X/cap/limit.sh" none >> "$OUT/night.log" 2>&1 || { echo "NIGHT ABORT cap/limit.sh failed" >> "$OUT/night.log"; exit 1; }
CAP_RESET=1 "$X/runner9.sh" "$OUT/b34" D9-H D9-S D9-H-m6 D9-S-m6 D9-H-m4 D9-S-m4
echo "NIGHT b34 done exit=$? $(date -Is)" >> "$OUT/night.log"
"$X/cap/limit.sh" none >> "$OUT/night.log" 2>&1
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
