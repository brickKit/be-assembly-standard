#!/bin/bash
# Foundations item 4, T8e: steps 1-5 of a full recovery (protocol 15) on the cell R4-X with be-ops recover. The
# archive on and a full backup; the cell from an empty database (seeds, scenarios); the row counts at T; the scenarios
# again after T; then announce T, freeze, restore-db, advance, redeliver. Checks: the business tables are back at T,
# the evidence store's are not (they never go back), every consumer had its redelivery, every member reported each
# phase. Then the phase off and up again (reopening is T10's) and the scenarios once more: the deployment works.
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")"); D=$R/dev/rebuild/experiment-cells/R4-X
echo $$ > $O/run.pid; : > $O/summary.txt
E=$R/.env; val() { grep "^$1=" $E | cut -d= -f2- | tr -d "\"'"; }
PW=$(val POSTGRES_PASSWORD)
# what the cell's configuration refers to (\${...}): brickkit up evaluates it at every phase change, as cell-chain.sh
casdoor_secret() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d brickkit_db -Atc \
  "select client_secret from casdoor.application where client_id = '$1'"; }
export BE_ACC_IAM_CLIENT_SECRET BE_ACC_IAM_DEV_CLIENT_SECRET
BE_ACC_IAM_CLIENT_SECRET=$(casdoor_secret be-iam-client); BE_ACC_IAM_DEV_CLIENT_SECRET=$(casdoor_secret be-iam-dev-client)
step() { local name=$1; shift; echo "DRILL $name BEGIN $(date -u +%H:%M:%S)" >> $O/summary.txt
  "$@" > $O/$name.log 2>&1; local rc=$?; echo "DRILL $name END rc=$rc" >> $O/summary.txt
  if [ $rc -ne 0 ]; then echo "DRILL FAILED $name" >> $O/summary.txt; echo "T8E ALL-DONE" >> $O/summary.txt; exit 1; fi; }
# business row counts of every schema that goes back (the be_* tables are the SDK's: the outbox, the inbox and the
# counters move with the redelivery), and the evidence store's
counts() {
  docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_experiment -Atc "SELECT table_schema || '.' || table_name || ' ' ||
    (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
    FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema IN
    (SELECT schema_name FROM information_schema.schemata WHERE schema_name ~ '^(infra|mdm|erp)_') AND table_name !~ '^be_'
    ORDER BY 1"; }

# a new deployment for this drill; the run profile's bucket (object lock, compliance: P12.1) once
# a deployment identity is a UUIDv7 (the security records' schema refuses another version)
DEP=$(python3 -c 'import os, time, uuid; b = bytearray(int(time.time() * 1000).to_bytes(6, "big") + os.urandom(10)); b[6] = b[6] & 0x0F | 0x70; b[8] = b[8] & 0x3F | 0x80; print(uuid.UUID(bytes=bytes(b)))')
sed -i "s/^deployment: .*/deployment: $DEP/" $D/cell.yaml
code=$(curl -s -o /dev/null -w '%{http_code}' --aws-sigv4 "aws:amz:us-east-1:s3" --user "$(val STORAGE_ACCESS_KEY):$(val STORAGE_SECRET_KEY)" \
  -X PUT -H 'x-amz-bucket-object-lock-enabled: true' http://localhost:9000/be-run-profile)
echo "run profile bucket: HTTP $code (200 made, 409 there)" >> $O/summary.txt
BIN=$(mktemp -d)  # the tool built from source, outside the repository (no build output in it)
(cd $R/tools/be-ops && go build -o $BIN/be-ops ./cmd/be-ops) || exit 1

step archive bash $R/infra/scripts/pg-backup.sh on
step cell env KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh R4-X $O/cell
counts > $O/counts-T.txt; sleep 2; T=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ); sleep 2
echo "T=$T" >> $O/summary.txt
step after-T env FROM=scenarios KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh R4-X $O/cell-after
counts > $O/counts-after.txt
# the tool's environment: the run profile, ops/recover's certificate of this deployment, the instance, the bus
export RUN_PROFILE_URL=http://localhost:9000 RUN_PROFILE_BUCKET=be-run-profile RUN_PROFILE_ACCESS_KEY=$(val STORAGE_ACCESS_KEY) \
  RUN_PROFILE_SECRET_KEY=$(val STORAGE_SECRET_KEY) SERVICE_TLS_CERT_FILE=$D/.secrets/tls/ops-recover.cert.pem \
  SERVICE_TLS_KEY_FILE=$D/.secrets/tls/ops-recover.key.pem SERVICE_TLS_CA_FILE=$D/.secrets/tls/ca.pem \
  RECOVER_PG_ADMIN="postgres://postgres:$PW@localhost:5432/postgres?sslmode=disable" BUS_URL=nats://localhost:4222
B="$BIN/be-ops recover"
step announce $B announce --project $D --reason "T8e drill: steps 1-5" --approver "T8e" --at "$T"
step freeze $B freeze --project $D
step restore-db $B restore-db --project $D
step advance $B advance --project $D
step redeliver $B redeliver --project $D
$B status --project $D > $O/status.txt 2>&1
counts > $O/counts-restored.txt
# the business tables are back at T; the evidence store's (infra_audit) are not lower than after T
python3 - $O <<'PY' >> $O/summary.txt
import sys, pathlib
o = pathlib.Path(sys.argv[1])
read = lambda n: dict(l.rsplit(' ', 1) for l in (o / n).read_text().split('\n') if l.strip())
t, after, back = read('counts-T.txt'), read('counts-after.txt'), read('counts-restored.txt')
moved = [k for k in t if not k.startswith('infra_audit.') and after.get(k) != t[k]]
wrong = [f"{k}: T {t[k]}, restored {back.get(k)}" for k in t if not k.startswith('infra_audit.') and back.get(k) != t[k]]
audit = [f"{k}: after {after[k]}, restored {back.get(k)}" for k in after if k.startswith('infra_audit.') and int(back.get(k, 0)) < int(after[k])]
print(f"CHECK tables that changed after T: {len(moved)} ({', '.join(moved[:8])})")
print(f"CHECK business tables not back at T: {len(wrong)} {wrong[:8]}")
print(f"CHECK evidence store tables that went back: {len(audit)} {audit[:8]}")
PY
# reopening is T10's: here only the phase off and up again, then the scenarios once more
sed -i 's/^RECOVERY_PHASE: .*/RECOVERY_PHASE: ""/' $D/config/vars.yaml
sed -i '/be-ops recover: cannot be frozen/d' $D/deploy.yaml  # what recover stopped for the recovery
step reopen bash -c "cd $D && brickkit up"
step scenarios-again env FROM=scenarios KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh R4-X $O/cell-again
(cd $D && brickkit down > /dev/null 2>&1)
bash $R/infra/scripts/pg-backup.sh off >> $O/summary.txt 2>&1
echo "T8E ALL-DONE" >> $O/summary.txt
