#!/bin/bash
# The cost of backing up and restoring to a point in time under four layouts of the same business data (foundations
# item 4, T11d; protocol 15's step 3: the business databases go back to T, the evidence store does not). pgBackRest
# 2.58 on PostgreSQL 16 (the image of infra/postgres/Dockerfile), the project's settings (process-max=1, the default
# compression), every instance in its own container with its own repository volume.
#   shared  one instance, one database: 12 component schemas and the evidence store's schema. To T: the instance
#           restored into a temporary one, the 12 schemas copied back (pg_dump | psql), as be-ops recover does
#   perdb   one instance, a database per component (12) and the evidence store's. To T: the same, database by database
#   split   the business data alone in its instance (one database, 12 schemas); the evidence store elsewhere. To T:
#           the instance restored in place (pgBackRest restore --delta, recovery to T, promote)
#   multi   the business data in 3 instances (4 schemas each, a third of the data each), restored in place in parallel
# Each round: a full backup, a fifth of every table's rows updated (WAL to replay), T, a hundredth more (lost), the
# restore to T, the restored sums checked against the ones read at T. Times are wall clock (ms); CPU is the
# containers' cgroup usage (ms) plus pgBackRest's own user+sys (time -p), so a run's every process is counted.
# Usage: bench.sh <out dir> <business MB> <rounds>      (env IMAGE: the PostgreSQL + pgBackRest image)
set -euo pipefail
O=$1 MB=$2 ROUNDS=$3
IMAGE=${IMAGE:-be-postgres-pgbackrest:16.15-alpine-2.58.0}
mkdir -p "$O"; echo $$ > "$O/run.pid"
W=$(mktemp -d); P=t11cost
OUT=$O/results.tsv
[ -s "$OUT" ] || printf 'size_mb\tround\tlayout\tbackup_ms\tbackup_cpu_ms\trepo_mb\trestore_ms\trestore_cpu_ms\tcopy_ms\tcopy_cpu_ms\ttotal_ms\tchecked\n' > "$OUT"
ms() { date +%s%3N; }
cpu() { local id; id=$(docker inspect -f '{{.Id}}' "$1"); awk '/^usage_usec/ {print int($2/1000)}' "/sys/fs/cgroup/system.slice/docker-$id.scope/cpu.stat"; }
q() { docker exec -u postgres "$1" psql -qAt -v ON_ERROR_STOP=1 -d "${3:-postgres}" -c "$2"; }
# pgBackRest's user+sys (ms) from busybox time -p's lines on stderr
tcpu() { awk '/^user|^sys/ {s += $2} END {print int(s * 1000)}' "$1"; }
cleanup() { mkdir -p "$O/containers"  # every container's log kept before it goes (a failure is read from them)
  for c in $(docker ps -a --format '{{.Names}}' | grep "^$P-"); do docker logs "$c" > "$O/containers/$c.log" 2>&1; done
  for c in $(docker ps -a --format '{{.Names}}' | grep "^$P-"); do docker rm -f "$c" >/dev/null; done
  for v in $(docker volume ls -q | grep "^$P-"); do docker volume rm -f "$v" >/dev/null; done; }
trap cleanup EXIT
cat > "$W/pgbackrest.conf" <<'EOF'
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=1
process-max=1
start-fast=y
log-level-console=warn
log-level-file=off

[main]
pg1-path=/var/lib/postgresql/data
EOF

# an instance with its WAL archived to its own repository
start() { local n=$P-$1
  docker volume create "$n-data" >/dev/null; docker volume create "$n-repo" >/dev/null
  docker run --rm -u root -v "$n-repo":/var/lib/pgbackrest --entrypoint chown "$IMAGE" postgres:postgres /var/lib/pgbackrest
  docker run -d --name "$n" -e POSTGRES_PASSWORD=bench -v "$n-data":/var/lib/postgresql/data -v "$n-repo":/var/lib/pgbackrest \
    -v "$W/pgbackrest.conf":/etc/pgbackrest/pgbackrest.conf:ro "$IMAGE" postgres -c wal_level=replica -c archive_mode=on \
    -c "archive_command=pgbackrest --stanza=main archive-push %p" -c max_wal_size=8GB -c shared_buffers=512MB >/dev/null
  for _ in $(seq 1 120); do q "$n" "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
  docker exec -u postgres "$n" pgbackrest --stanza=main stanza-create >/dev/null; }
# a component's table of mb megabytes (about 150 bytes a row with its index)
fill() { local n=$1 db=$2 sch=$3 mb=$4; local rows=$(( mb * 1024 * 1024 / 150 ))
  q "$n" "CREATE SCHEMA IF NOT EXISTS $sch; CREATE TABLE $sch.t (id bigint PRIMARY KEY, a text NOT NULL, b numeric NOT NULL, c timestamptz NOT NULL);
    INSERT INTO $sch.t SELECT g, md5(g::text) || md5((g + 1)::text), (g % 100000) / 100.0, now() FROM generate_series(1, $rows) g;
    CREATE INDEX ON $sch.t (c); ANALYZE $sch.t" "$db" >/dev/null; }
change() { local n=$1 db=$2 sch=$3 mod=$4; q "$n" "UPDATE $sch.t SET b = b + 1, c = now() WHERE id % $mod = 0" "$db" >/dev/null; }
sum() { q "$1" "SELECT sum(b) FROM $3.t" "$2"; }
backup() { local n=$P-$1; docker exec -u postgres "$n" sh -c 'time -p pgbackrest --stanza=main --type=full backup' 2> "$W/bt"; }
repo_mb() { docker run --rm -v "$P-$1-repo":/r:ro --entrypoint du "$IMAGE" -sm /r | cut -f1; }
# the WAL up to now switched out and archived: the segment just ended is in the repository (a fixed wait was not
# enough at 1 GB: the restore ran out of WAL before T, "recovery ended before configured recovery target was reached")
archived() { local seg; seg=$(q "$1" "SELECT pg_walfile_name(pg_switch_wal())")
  for _ in $(seq 1 1200); do [ "$(q "$1" "SELECT coalesce(last_archived_wal >= '$seg', false) FROM pg_stat_archiver")" = t ] && return 0; sleep 0.5; done
  echo "the archive did not reach $seg in 10 minutes" >&2; return 1; }
pgtime() { q "$1" "SET TimeZone = 'UTC'; SELECT now()"; }
# in place: stop, restore with --delta to T, start, wait until promoted
inplace() { local n=$P-$1 t=$2
  docker stop "$n" >/dev/null
  docker run --rm -u postgres -v "$n-data":/var/lib/postgresql/data -v "$n-repo":/var/lib/pgbackrest \
    -v "$W/pgbackrest.conf":/etc/pgbackrest/pgbackrest.conf:ro --entrypoint sh "$IMAGE" -c \
    "time -p pgbackrest --stanza=main --delta --type=time '--target=$t' --target-action=promote restore" 2> "$W/rt-$1" >/dev/null
  local c0; docker start "$n" >/dev/null; c0=$(cpu "$n")
  for _ in $(seq 1 1800); do [ "$(q "$n" 'SELECT NOT pg_is_in_recovery()' 2>/dev/null)" = t ] && break; sleep 0.2; done
  [ "$(q "$n" 'SELECT NOT pg_is_in_recovery()')" = t ]
  echo $(( $(tcpu "$W/rt-$1") + $(cpu "$n") - c0 )) > "$W/rc-$1"; }
# into a temporary instance (the live one untouched), then the given schemas or databases copied back
temp() { local n=$P-$1 t=$2 tmp=$P-$1-tmp
  docker volume create "$tmp-data" >/dev/null
  docker run --rm -u root -v "$tmp-data":/var/lib/postgresql/data --entrypoint chown "$IMAGE" postgres:postgres /var/lib/postgresql/data
  docker run --rm -u postgres -v "$tmp-data":/var/lib/postgresql/data -v "$n-repo":/var/lib/pgbackrest:ro \
    -v "$W/pgbackrest.conf":/etc/pgbackrest/pgbackrest.conf:ro --entrypoint sh "$IMAGE" -c \
    "time -p pgbackrest --stanza=main --type=time '--target=$t' --target-action=promote --archive-mode=off restore" 2> "$W/rt-$1" >/dev/null
  docker run -d --name "$tmp" -v "$tmp-data":/var/lib/postgresql/data -v "$n-repo":/var/lib/pgbackrest:ro \
    -v "$W/pgbackrest.conf":/etc/pgbackrest/pgbackrest.conf:ro "$IMAGE" postgres -c archive_mode=off -c shared_buffers=512MB >/dev/null
  local c0; c0=$(cpu "$tmp")
  for _ in $(seq 1 1800); do [ "$(q "$tmp" 'SELECT NOT pg_is_in_recovery()' 2>/dev/null)" = t ] && break; sleep 0.2; done
  [ "$(q "$tmp" 'SELECT NOT pg_is_in_recovery()')" = t ]
  echo $(( $(tcpu "$W/rt-$1") + $(cpu "$tmp") - c0 )) > "$W/rc-$1"; }

setup() {
  start shared; start perdb; start split; start multi1; start multi2; start multi3
  local each=$(( MB / 12 ))
  for i in $(seq -w 1 12); do
    fill $P-shared postgres c$i $each
    q $P-perdb "CREATE DATABASE c$i" >/dev/null; fill $P-perdb c$i c $each
    fill $P-split postgres c$i $each
    fill $P-multi$(( (10#$i - 1) / 4 + 1 )) postgres c$i $each
  done
  fill $P-shared postgres audit 16; q $P-perdb "CREATE DATABASE audit" >/dev/null; fill $P-perdb audit audit 16
}
# the (instance, database, schema) of each component's data in a layout
parts() { for i in $(seq -w 1 12); do case $1 in
  shared|split) echo "$P-$1 postgres c$i" ;; perdb) echo "$P-perdb c$i c" ;;
  multi) echo "$P-multi$(( (10#$i - 1) / 4 + 1 )) postgres c$i" ;; esac; done; }
insts() { case $1 in multi) echo multi1 multi2 multi3 ;; *) echo "$1" ;; esac; }

run() { local L=$1 r=$2 b0 bc=0 t0 rc=0 cms=0 ccpu=0 at
  b0=$(ms); for i in $(insts $L); do backup $i; bc=$(( bc + $(tcpu "$W/bt") )); done; local bms=$(( $(ms) - b0 ))
  # the backups are taken one after another for multi (the archive and the repositories are per instance)
  local repo=0; for i in $(insts $L); do repo=$(( repo + $(repo_mb $i) )); done
  while read -r n db s; do change "$n" "$db" "$s" 5; done < <(parts $L)
  declare -A AT; while read -r n db s; do AT["$n/$db/$s"]=$(sum "$n" "$db" "$s"); done < <(parts $L)
  sleep 1; at=$(pgtime $P-$(insts $L | cut -d' ' -f1)); sleep 1
  while read -r n db s; do change "$n" "$db" "$s" 100; done < <(parts $L)
  for i in $(insts $L); do archived $P-$i; done  # the WAL through T in the archive before restoring to T
  t0=$(ms)
  case $L in
    split) inplace split "$at"; rc=$(cat "$W/rc-split") ;;
    multi) for i in 1 2 3; do inplace multi$i "$at" & done; wait; for i in 1 2 3; do rc=$(( rc + $(cat "$W/rc-multi$i") )); done ;;
    shared|perdb)
      temp $L "$at"; rc=$(cat "$W/rc-$L"); local c0=$(ms) l0 t0c; l0=$(cpu $P-$L); t0c=$(cpu $P-$L-tmp)
      if [ $L = shared ]; then
        for i in $(seq -w 1 12); do q $P-shared "DROP SCHEMA c$i CASCADE" >/dev/null
          docker exec -u postgres $P-shared-tmp pg_dump -d postgres -n c$i | docker exec -i -u postgres $P-shared psql -v ON_ERROR_STOP=1 -qAt -d postgres >/dev/null; done
      else
        for i in $(seq -w 1 12); do q $P-perdb "DROP DATABASE c$i WITH (FORCE)" >/dev/null; q $P-perdb "CREATE DATABASE c$i" >/dev/null
          docker exec -u postgres $P-perdb-tmp pg_dump -d c$i | docker exec -i -u postgres $P-perdb psql -v ON_ERROR_STOP=1 -qAt -d c$i >/dev/null; done
      fi
      cms=$(( $(ms) - c0 )); ccpu=$(( $(cpu $P-$L) - l0 + $(cpu $P-$L-tmp) - t0c ))
      docker rm -f $P-$L-tmp >/dev/null; docker volume rm $P-$L-tmp-data >/dev/null ;;
  esac
  local total=$(( $(ms) - t0 )) ok=yes
  while read -r n db s; do [ "$(sum "$n" "$db" "$s")" = "${AT[$n/$db/$s]}" ] || ok=no; done < <(parts $L)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$MB" "$r" "$L" "$bms" "$bc" "$repo" "$(( total - cms ))" "$rc" "$cms" "$ccpu" "$total" "$ok" >> "$OUT"
  echo "BENCH $MB MB round $r $L: backup ${bms} ms, restore ${total} ms (copy ${cms} ms), checked $ok"
}

echo "BENCH setup $MB MB $(date +%H:%M:%S)"; setup; echo "BENCH setup done $(date +%H:%M:%S)"
read -r -a LAYOUTS <<< "${LAYOUTS:-shared perdb split multi}"  # env LAYOUTS: a subset, e.g. to reproduce one
for r in $(seq 1 "$ROUNDS"); do
  nlayouts=${#LAYOUTS[@]}  # not n: run() reads parts into n
  for k in $(seq 0 $(( nlayouts - 1 ))); do run "${LAYOUTS[$(( (k + r - 1) % nlayouts ))]}" "$r"; done  # the order rotates each round
done
echo "BENCH $MB MB ALL-DONE"
