#!/bin/bash
# Step 10 (step10-plan.md 5.6): how much private memory each PostgreSQL backend holds, per login role, in a single-run
# cell against a shell cell, one batch. Per cell: brought up with seed data (cell-chain.sh), the baseline, a short mix
# so that every component has touched its tables, then one snapshot: for every backend of the experiment database,
# its role and its RssAnon and RssShmem (/proc inside be-postgres: private memory, and the shared buffers it mapped),
# summed per role; and the container's own anon. Memory only: no power mode or quiet machine needed.
# Usage: pgmem.sh <out> <cell>...
set -u
OUT=$(realpath -m "$1"); shift
R=/home/zhijie/Desktop/github/be-assembly-standard; X=$R/dev/rebuild/experiment-scripts
CONF=${CONF:-$R/tools/be-acceptance/conformance}; export CONF
mkdir -p "$OUT"; echo $$ > "$OUT/runner.pid"
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export BE_ACC_NATS_URL=nats://localhost:4222
export BE_ACC_PG_ADMIN; BE_ACC_PG_ADMIN="postgres://postgres:$(envval POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
log() { echo "$* $(date -Is)" >> "$OUT/status.log"; }
snapshot() {  # one line per backend: role pid RssAnon RssShmem (kB)
  docker exec -e PGPASSWORD="$(envval POSTGRES_PASSWORD)" be-postgres sh -c '
    psql -U postgres -d postgres -Atc "select usename, pid from pg_stat_activity where datname = '"'"'be_experiment'"'"' and backend_type = '"'"'client backend'"'"'" |
    while IFS="|" read u p; do
      a=$(awk "/^RssAnon/ {print \$2}" /proc/$p/status 2>/dev/null); s=$(awk "/^RssShmem/ {print \$2}" /proc/$p/status 2>/dev/null)
      [ -n "$a" ] && echo "$u $p $a $s"
    done'
}
for CELL in "$@"; do
  D=$R/dev/rebuild/experiment-cells/$CELL; mkdir -p "$OUT/$CELL"
  log "CELL $CELL"
  if ! KEEP_UP=1 "$X/cell-chain.sh" "$CELL" "$OUT/$CELL/up" > "$OUT/$CELL/up.log" 2>&1; then log "CELL $CELL FAILED up"; (cd "$D" && brickkit down) >/dev/null 2>&1; continue; fi
  (cd "$CONF" && uv run python -m cells baseline "$D" "$OUT/$CELL/world.json") > "$OUT/$CELL/baseline.log" 2>&1 || log "CELL $CELL FAILED baseline"
  (cd "$CONF" && uv run python -m cells chain "$D" "$OUT/$CELL/run" --world "$OUT/$CELL/world.json" --rate 7 --users 20 \
    --idle 0 --warmup 30 --seconds 120) > "$OUT/$CELL/chain.log" 2>&1 || log "CELL $CELL FAILED chain"
  snapshot > "$OUT/$CELL/backends.txt"
  awk '{n[$1]++; a[$1]+=$3; s[$1]+=$4; N++; A+=$3; S+=$4}
       END {for (u in n) printf "%-22s backends %3d  anon %7.1f MiB (%.1f each)  shmem %7.1f MiB\n", u, n[u], a[u]/1024, a[u]/1024/n[u], s[u]/1024;
            printf "%-22s backends %3d  anon %7.1f MiB (%.1f each)  shmem %7.1f MiB\n", "TOTAL", N, A/1024, A/1024/N, S/1024}' \
    "$OUT/$CELL/backends.txt" | sort > "$OUT/$CELL/per-role.txt"
  g=/sys/fs/cgroup$(cut -d: -f3 /proc/"$(docker inspect -f '{{.State.Pid}}' be-postgres)"/cgroup)
  echo "be-postgres cgroup: anon $(awk '$1=="anon" {printf "%.0f", $2/1048576}' "$g/memory.stat") MiB, shmem $(awk '$1=="shmem" {printf "%.0f", $2/1048576}' "$g/memory.stat") MiB" >> "$OUT/$CELL/per-role.txt"
  log "CELL $CELL snapshot $(grep TOTAL "$OUT/$CELL/per-role.txt")"
  (cd "$D" && brickkit down) > "$OUT/$CELL/down.log" 2>&1
done
log ALL-DONE
