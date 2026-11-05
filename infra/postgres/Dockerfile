# be-postgres with pgBackRest (foundations item 4, A135): the official image, the backup tool of the Alpine release it
# is built on, pinned. Physical backups and the WAL archive for a full recovery to a point in time (protocol 15).
FROM postgres:16.15-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea
RUN apk add --no-cache pgbackrest=2.58.0-r0 \
 && mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest /etc/pgbackrest \
 && chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
