#!/bin/bash
# be-postgres's backups with pgBackRest (foundations item 4, A135; protocol 15, step 3 of a full recovery).
#
#   pg-backup.sh on                 turn the WAL archive on and take a full backup (a drill starts here)
#   pg-backup.sh off                turn the archive off: the WAL is let go again (development machines, disk)
#   pg-backup.sh backup [full|diff] take a backup (the archive must be on)
#   pg-backup.sh status             whether the archive is on, and the repository's backups and WAL range
#   pg-backup.sh record             record the repository's latest backup in the run profile (on and backup do it)
#   pg-backup.sh restore-to T NAME PORT
#                                   restore the instance as it was at T (RFC 3339 or PostgreSQL's timestamptz) into a
#                                   temporary instance: container NAME, its own volume, listening on PORT on the host.
#                                   be-postgres is not touched; the recovery tool copies schemas back from NAME.
#   pg-backup.sh drop-temp NAME     remove a temporary instance and its volume
#
# The record (be-protocol P15.21): components release an archive unit's online rows only after a backup that finished
# after the unit was published, read from the run profile's kind backup. With BE_OPS_RECORD (the be-ops binary) and
# BE_OPS_PROJECT (the BrickKit project's directory) set, and be-ops recover's environment (its certificate and the run
# profile, the same as for a recovery), record calls `be-ops recover backup-record`; without them it only says so.
#
# Off by default on a development machine: a WAL archive kept without regular full backups grows without bound
# (infra/postgres/pgbackrest/archive.sh). A production deployment keeps it on with scheduled backups.
set -euo pipefail
PG=be-postgres
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$PG")
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONF=$ROOT/infra/postgres/pgbackrest/pgbackrest.conf
ex() { docker exec -u postgres "$PG" "$@"; }

# the repository's latest backup into the run profile: its label and when it stopped (RFC 3339, UTC)
record() {
  local latest
  latest=$(ex pgbackrest --stanza=main info --output=json | python3 -c '
import json, sys, datetime
b = json.load(sys.stdin)[0]["backup"]
if b:
    stop = datetime.datetime.fromtimestamp(b[-1]["timestamp"]["stop"], datetime.timezone.utc)
    print(b[-1]["label"], stop.strftime("%Y-%m-%dT%H:%M:%SZ"))')
  [ -n "$latest" ] || { echo "the repository holds no backup: nothing to record" >&2; return 1; }
  set -- $latest
  if [ -z "${BE_OPS_RECORD:-}" ] || [ -z "${BE_OPS_PROJECT:-}" ]; then
    echo "backup $1 (finished $2) not recorded: BE_OPS_RECORD and BE_OPS_PROJECT unset, archive units are not released"
    return 0
  fi
  "$BE_OPS_RECORD" recover backup-record --project "$BE_OPS_PROJECT" --backup "$1" --finished-at "$2"
}

case "${1:-}" in
on)
  docker exec "$PG" chown -R postgres:postgres /var/lib/pgbackrest
  ex pgbackrest --stanza=main stanza-create 2>&1 | tail -1
  ex touch /var/lib/pgbackrest/ARCHIVING
  ex psql -qAt -c "SELECT pg_switch_wal()" >/dev/null
  ex pgbackrest --stanza=main check 2>&1 | tail -1
  ex pgbackrest --stanza=main --type=full backup 2>&1 | tail -1
  record
  ;;
off)
  ex rm -f /var/lib/pgbackrest/ARCHIVING
  echo "the WAL archive is off"
  ;;
backup)
  ex test -f /var/lib/pgbackrest/ARCHIVING || { echo "the archive is off: pg-backup.sh on" >&2; exit 1; }
  ex pgbackrest --stanza=main --type="${2:-diff}" backup 2>&1 | tail -1
  record
  ;;
record)
  record
  ;;
status)
  if ex test -f /var/lib/pgbackrest/ARCHIVING; then echo "archive: on"; else echo "archive: off"; fi
  ex pgbackrest --stanza=main info 2>&1 | sed -n '1,40p'
  ;;
restore-to)
  T=${2:?T}; NAME=${3:?NAME}; PORT=${4:?PORT}
  # pgBackRest takes PostgreSQL's own form of a time (2026-11-05 14:17:21.743696+00), not RFC 3339's T and Z: the
  # instance writes T in it, in UTC
  T=$(ex psql -qAt -c "SET TimeZone = 'UTC'; SELECT '$T'::timestamptz")
  # a recovering instance may not have fewer connections (and the like) than the one that wrote the WAL
  MAXCONN=$(ex psql -qAt -c "SHOW max_connections"); PRELOAD=$(ex psql -qAt -c "SHOW shared_preload_libraries")
  # the WAL up to now switched out, and the restore waits until the archive holds the segment just ended: a fixed wait
  # is not enough after much writing (the archive compresses one segment at a time; T11d at 1 GB ran out of WAL before T)
  # recovery to a time stops at the first commit after it: on a database with no write since T there is none, and
  # the recovery ends before its target (FATAL). A transaction that only takes an ID commits now, after T.
  ex psql -qAt -c "SELECT txid_current()" >/dev/null
  SEG=$(ex psql -qAt -c "SELECT pg_walfile_name(pg_switch_wal())")
  for _ in $(seq 1 1200); do
    [ "$(ex psql -qAt -c "SELECT coalesce(last_archived_wal >= '$SEG', false) FROM pg_stat_archiver")" = t ] && break
    sleep 0.5
  done
  [ "$(ex psql -qAt -c "SELECT coalesce(last_archived_wal >= '$SEG', false) FROM pg_stat_archiver")" = t ] ||
    { echo "the WAL archive has not reached $SEG within 10 minutes: T may not be restorable" >&2; exit 1; }
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker volume rm -f "$NAME-data" >/dev/null 2>&1 || true
  docker volume create "$NAME-data" >/dev/null
  REPO=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/pgbackrest"}}{{.Name}}{{end}}{{end}}' "$PG")
  docker run --rm -u root -v "$NAME-data":/var/lib/postgresql/data --entrypoint chown "$IMAGE" postgres:postgres /var/lib/postgresql/data
  docker run --rm -u postgres -v "$NAME-data":/var/lib/postgresql/data -v "$REPO":/var/lib/pgbackrest:ro \
    -v "$CONF":/etc/pgbackrest/pgbackrest.conf:ro --entrypoint pgbackrest "$IMAGE" \
    --stanza=main --type=time "--target=$T" --target-action=promote --archive-mode=off restore 2>&1 |
    grep -E "ERROR|WARN|restore command end" | head -5
  # the temporary instance replays the archive up to T (its restore_command is pgBackRest's archive-get: the
  # repository and the configuration, read only) and archives nothing: it only serves the copy back
  docker run -d --name "$NAME" -p "$PORT:5432" -v "$NAME-data":/var/lib/postgresql/data \
    -v "$REPO":/var/lib/pgbackrest:ro -v "$CONF":/etc/pgbackrest/pgbackrest.conf:ro "$IMAGE" \
    postgres -c archive_mode=off -c "max_connections=$MAXCONN" -c "shared_preload_libraries=$PRELOAD" >/dev/null
  # ready means accepting connections, which a hot standby still replaying does: wait until the replay to T is done
  # and the instance promoted (out of recovery), or a copy taken now is a state before T (the T8e drill's billing)
  for _ in $(seq 1 600); do
    [ "$(docker exec -u postgres "$NAME" psql -qAt -c 'SELECT NOT pg_is_in_recovery()' 2>/dev/null)" = t ] && break
    sleep 1
  done
  [ "$(docker exec -u postgres "$NAME" psql -qAt -c 'SELECT NOT pg_is_in_recovery()' 2>/dev/null)" = t ] ||
    { echo "the temporary instance did not finish its recovery to T" >&2; exit 1; }
  docker exec -u postgres "$NAME" psql -qAt -c "SELECT 'restored to ' || '$T' || ', timeline ' || timeline_id FROM pg_control_checkpoint()"
  ;;
drop-temp)
  NAME=${2:?NAME}
  docker rm -f "$NAME" >/dev/null
  docker volume rm "$NAME-data" >/dev/null
  echo "removed $NAME"
  ;;
*)
  sed -n '2,15p' "$0"; exit 64
  ;;
esac
