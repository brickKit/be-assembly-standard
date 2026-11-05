FROM postgres:16.15-alpine
RUN apk add --no-cache pgbackrest=2.58.0-r0 && mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest && chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
