#!/bin/bash
# T8c: be-postgres with pgBackRest. Archive on and a full backup, write A, take T, write B, restore to T into a
# temporary instance: it has A only; be-postgres still has both; then the temporary instance goes and the archive is
# off again. A scratch database of its own, dropped at the end.
set -eu
R=/home/zhijie/Desktop/github/be-assembly-standard; B=$R/infra/scripts/pg-backup.sh
q() { docker exec -u postgres be-postgres psql -qAt -d "${2:-postgres}" -c "$1"; }
echo "image: $(docker inspect -f '{{.Config.Image}}' be-postgres)"
echo "archive_mode: $(q 'SHOW archive_mode'), archive_command: $(q 'SHOW archive_command')"
q "DROP DATABASE IF EXISTS t8smoke"; q "CREATE DATABASE t8smoke"
bash $B on
q "CREATE TABLE t (v text); INSERT INTO t VALUES ('A')" t8smoke
sleep 1; T=$(q "SELECT now()"); sleep 1
q "INSERT INTO t VALUES ('B')" t8smoke
echo "T=$T"
bash $B restore-to "$T" t8-restore 15439
echo "temporary instance at T: $(docker exec -u postgres t8-restore psql -qAt -d t8smoke -c "SELECT string_agg(v, ',' ORDER BY v) FROM t")"
echo "be-postgres now: $(q "SELECT string_agg(v, ',' ORDER BY v) FROM t" t8smoke)"
bash $B drop-temp t8-restore
bash $B status | head -3
bash $B off
q "DROP DATABASE t8smoke"
echo "SMOKE DONE"
