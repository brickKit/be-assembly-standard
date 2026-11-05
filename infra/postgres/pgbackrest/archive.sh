#!/bin/sh
# archive_command of be-postgres (%p is the WAL file). The archive is on only while the repository holds the file
# ARCHIVING (infra/scripts/pg-backup.sh on|off): on a development machine a WAL archive kept without regular full
# backups grows without bound, so it is on for a recovery drill and off otherwise, and off means the WAL is let go as
# before. A production deployment keeps it on with scheduled backups (the operations guide).
[ -f /var/lib/pgbackrest/ARCHIVING ] || exit 0
exec pgbackrest --stanza=main archive-push "$1"
