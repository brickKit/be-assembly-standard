#!/bin/bash
# pgBackRest 2.58.0 on postgres:16.15-alpine: full backup, WAL archive, point-in-time restore to T. Throwaway volumes.
set -eu
N=pgbr-smoke; docker rm -f $N >/dev/null 2>&1 || true; docker volume rm -f pgbr-data pgbr-repo >/dev/null 2>&1 || true
docker run -d --name $N -e POSTGRES_PASSWORD=smoke -v pgbr-data:/var/lib/postgresql/data -v pgbr-repo:/var/lib/pgbackrest \
  -v $PWD/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro pgbr-smoke:16.15 \
  -c archive_mode=on -c "archive_command=pgbackrest --stanza=main archive-push %p" -c wal_level=replica >/dev/null
until docker exec $N pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done; sleep 2
ex() { docker exec -u postgres $N "$@"; }
ex chown postgres /var/lib/pgbackrest 2>/dev/null || docker exec $N chown -R postgres:postgres /var/lib/pgbackrest
ex pgbackrest --stanza=main stanza-create 2>&1 | tail -1
ex pgbackrest --stanza=main check 2>&1 | tail -1
ex pgbackrest --stanza=main --type=full backup 2>&1 | tail -1; sleep 2
ex psql -qAt -c "CREATE TABLE t(v text); INSERT INTO t VALUES ('A');"
T=$(ex psql -qAt -c "SELECT now()"); sleep 1
ex psql -qAt -c "INSERT INTO t VALUES ('B'); SELECT pg_switch_wal();" >/dev/null
sleep 3; ex pgbackrest --stanza=main info 2>&1 | grep -E "wal archive min/max|full backup" | head -2
echo "T=$T"
docker stop $N >/dev/null
docker run --rm -u postgres -v pgbr-data:/var/lib/postgresql/data -v pgbr-repo:/var/lib/pgbackrest \
  -v $PWD/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro --entrypoint pgbackrest pgbr-smoke:16.15 \
  --stanza=main --delta --type=time "--target=$T" --target-action=promote restore 2>&1 | grep -E "ERROR|WARN|INFO: restore command end" | head -5
docker start $N >/dev/null; until docker exec $N pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done; sleep 2
echo "rows after restore to T: $(ex psql -qAt -c "SELECT string_agg(v, ',' ORDER BY v) FROM t")"
echo "timeline: $(ex psql -qAt -c "SELECT timeline_id FROM pg_control_checkpoint()")"
docker rm -f $N >/dev/null; docker volume rm pgbr-data pgbr-repo >/dev/null
