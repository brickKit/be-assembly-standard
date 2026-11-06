#!/bin/bash
# Foundations item 4, T11: the gate's recovery drill. Steps 1-10 of a full recovery (protocol 15) on the cell R4-G with
# be-ops recover, timed, and protocol 15's eight drill scenarios ("恢复目标与演练"):
#   1 an external payment after T: r-after paid after T (external only after the recovery: not to be entered again)
#   2 a revocation after T: test.mdm.viewer's grant revoked (back by its evidence)
#   3 a consumer two days behind at T: erp/sales stopped, a unit renamed, the rename's outbox rows dated two days back;
#     T; sales back (it catches up after T, which the restore undoes); the redelivery covers its progress
#   4 an intent-only disablement: test.expired, its row locked until the intent is in the evidence store, the store
#     (infra/audit alone) then paused: the conclusion never leaves the identity member
#   5 a disablement only in the alert channel: test.rates, disabled while the store is paused
#   6 accounts whose password and second factors changed after T, one an authorization admin: test.unit.admin.cn's
#     password changed in Casdoor; test.mdm.viewer's second factor (added before T) reset by test.mdm.admin. Casdoor
#     is outside the recovery group: 6.7 checks them (consistent), the new password signs in
#   7 a payment executed outside and unknown here: r-after again (external only, not to be entered again)
#   8 a pending payment past the dedupe window: r-stale refused (429) until the failure, the window 61 minutes, so its
#     resend deadline (first send + 61 min - 1 h) has passed at the reconciliation (attempt 4's 65 minutes left it ahead)
# The failure: the shell be/go-infra killed while the evidence store is paused (both disablements' conclusions are in
# the identity member's outbox), then the store resumes and the recovery starts.
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")"); D=$R/dev/rebuild/experiment-cells/R4-G
echo $$ > $O/run.pid; : > $O/summary.txt
sql() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_experiment -Atc "$1"; }
E=$R/.env; val() { grep "^$1=" $E | cut -d= -f2- | tr -d "\"'"; }
PW=$(val POSTGRES_PASSWORD)
casdoor_secret() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d brickkit_db -Atc \
  "select client_secret from casdoor.application where client_id = '$1'"; }
export BE_ACC_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY; BE_ACC_S3_ACCESS_KEY=$(val STORAGE_ACCESS_KEY); BE_ACC_S3_SECRET_KEY=$(val STORAGE_SECRET_KEY)
export BE_ACC_IAM_CLIENT_SECRET BE_ACC_IAM_DEV_CLIENT_SECRET
BE_ACC_IAM_CLIENT_SECRET=$(casdoor_secret be-iam-client); BE_ACC_IAM_DEV_CLIENT_SECRET=$(casdoor_secret be-iam-dev-client)
export CASDOOR_URL=http://localhost:8000 CASDOOR_ADMIN_PASSWORD; CASDOOR_ADMIN_PASSWORD=$(val CASDOOR_ADMIN_PASSWORD)
ms() { date -u +%s%3N; }
step() { local name=$1; shift; local t0; t0=$(ms); echo "DRILL $name BEGIN $(date -u +%H:%M:%S)" >> $O/summary.txt
  "$@" > $O/$name.log 2>&1; local rc=$?; echo "DRILL $name END rc=$rc $(( $(ms) - t0 )) ms" >> $O/summary.txt
  if [ $rc -ne 0 ]; then echo "DRILL FAILED $name" >> $O/summary.txt; echo "T11 ALL-DONE" >> $O/summary.txt; exit 1; fi; }
counts() {
  docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_experiment -Atc "SELECT table_schema || '.' || table_name || ' ' ||
    (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
    FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema IN
    (SELECT schema_name FROM information_schema.schemata WHERE schema_name ~ '^(infra|mdm|erp)_') AND table_name !~ '^be_'
    ORDER BY 1"; }
container() { docker ps -a --filter label=com.docker.compose.project=brickkit-r4-g --format '{{.Names}}' | grep -- "$1" | head -1; }
# wait until a query answers non-zero (the cell's database), at most $2 seconds
until_sql() { local q=$1 n=$2; for _ in $(seq 1 "$n"); do [ "$(sql "$q")" != "0" ] && return 0; sleep 1; done; echo "not within ${n}s: $q"; return 1; }
evidence_of() { echo "select count(*) from infra_audit.audit_evidence where category = '$1' and phase = '$2' and convert_from(record, 'UTF8')::jsonb->'object'->>'id' = '$3'"; }

DEP=$(python3 -c 'import os, time, uuid; b = bytearray(int(time.time() * 1000).to_bytes(6, "big") + os.urandom(10)); b[6] = b[6] & 0x0F | 0x70; b[8] = b[8] & 0x3F | 0x80; print(uuid.UUID(bytes=bytes(b)))')
sed -i "s/^deployment: .*/deployment: $DEP/" $D/cell.yaml
code=$(curl -s -o /dev/null -w '%{http_code}' --aws-sigv4 "aws:amz:us-east-1:s3" --user "$(val STORAGE_ACCESS_KEY):$(val STORAGE_SECRET_KEY)" \
  -X PUT -H 'x-amz-bucket-object-lock-enabled: true' http://localhost:9000/be-run-profile)
echo "run profile bucket: HTTP $code (200 made, 409 there)" >> $O/summary.txt
BIN=$(mktemp -d)  # the tools built from source, outside the repository (no build output in it)
(cd $R/tools/be-ops && CGO_ENABLED=0 go build -o $BIN/be-ops ./cmd/be-ops) || exit 1  # static: the calls run in alpine
(cd $O/drilltool && go build -o $BIN/drilltool .) || exit 1
python3 -I $R/tools/be-acceptance/conformance/external/fake.py --port 18990 > $O/fake.log 2>&1 &
FAKE=$!; trap 'kill $FAKE 2>/dev/null; docker unpause "$(container infra-audit)" >/dev/null 2>&1' EXIT
P="python3 -I $R/dev/rebuild/foundations-04-data/t10e/pay.py"
C="python3 -I $O/casdoor.py"
T_TOOL=$BIN/drilltool
export IAM_URL=http://localhost:18200 AUTHZ_URL=http://localhost:18223 ORG_URL=http://localhost:18083
export BE_ACC_IAM_TEST_PASSWORD; BE_ACC_IAM_TEST_PASSWORD=$(val IAM_TEST_PASSWORD)
export PG_DSN="postgres://postgres:$PW@localhost:5432/be_experiment?sslmode=disable"

# earlier cells down first, then the test accounts as seeded in Casdoor (outside the recovery group)
for c in R4-X R4-G; do (cd $R/dev/rebuild/experiment-cells/$c && brickkit down > /dev/null 2>&1); done
(cd $R/components/infra/iam-casdoor && CASDOOR_URL=$CASDOOR_URL CASDOOR_ADMIN_PASSWORD=$CASDOOR_ADMIN_PASSWORD \
  IAM_TEST_PASSWORD=$(val IAM_TEST_PASSWORD) python3 -I scripts/dev_setup.py --users-only > /dev/null 2>&1) || exit 1
$C mfa-off test.mdm.viewer > $O/mfa-off.log 2>&1 || exit 1
# dev_setup.py's update-user does not set a password in Casdoor: the one this drill changes is set back by set-password
NEW_PASSWORD=$(val IAM_TEST_PASSWORD) $C password test.unit.admin.cn > $O/password-reset.log 2>&1 || exit 1
step archive bash $R/infra/scripts/pg-backup.sh on
step cell env KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh R4-G $O/cell
export AUDIT_CONTAINER; AUDIT_CONTAINER=$(container infra-audit); SALES=$(container erp-sales); SHELL_C=$(container go-infra)
echo "containers: audit $AUDIT_CONTAINER, sales $SALES, shell $SHELL_C" >> $O/summary.txt
step prepare $T_TOOL prepare
VIEWER=$(sql "select principal from infra_iam_casdoor.iam_account where username = 'brickkit/test.mdm.viewer'")
ADMINCN=$(sql "select principal from infra_iam_casdoor.iam_account where username = 'brickkit/test.unit.admin.cn'")
EXPIRED=$(sql "select principal from infra_iam_casdoor.iam_account where username = 'brickkit/test.expired'")
RATES=$(sql "select principal from infra_iam_casdoor.iam_account where username = 'brickkit/test.rates'")
# scenario 6, before T: test.mdm.viewer gets a second factor in Casdoor; the comparison records it (before T)
step mfa-before $C mfa-email test.mdm.viewer
step mfa-seen until_sql "$(evidence_of credential_tightening_in_product general $VIEWER)" 150
# scenarios 1, 7, 8: payments
step pay-before $P pay r-before
step pay-before-final $P wait r-before succeeded
step limit $P fake '{"faults": ["limit"], "faults_by_reference": {"r-stale": ["limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit","limit"]}}'
step pay-pending $P pay r-pending
step pay-pending-waits $P wait r-pending retry_wait  # sent again after the backoff (a minute): after T
step pay-stale $P pay r-stale
step pay-stale-waits $P wait r-stale retry_wait  # refused until the failure
STALE_FIRST=$(date -u +%H:%M:%S)
# scenario 3: sales stops; a unit it projects is renamed; the rename's events dated two days back
step sales-stop docker stop $SALES
RENAMED=$(sql "select u.id from mdm_org.org_unit u join mdm_org.legal_entity e on e.id = u.legal_entity_id where e.code = 'CN01' and u.state = 'active' and exists (select 1 from erp_sales.be_projection p where p.record_id = u.id::text) order by u.code desc limit 1")
step rename python3 -I - "$RENAMED" <<'PY'
import json, os, sys, urllib.request
unit = sys.argv[1]
def call(method, url, body=None, token=None, extra=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {}), **(extra or {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"{}")
tok = call("POST", os.environ["IAM_URL"] + "/api/iam/dev/token", {"username": "test.mdm.admin", "password": os.environ["BE_ACC_IAM_TEST_PASSWORD"]})["access_token"]
u = call("GET", os.environ["ORG_URL"] + "/api/org/units/" + unit, token=tok)
out = call("PATCH", os.environ["ORG_URL"] + "/api/org/units/" + unit, {"version": u["version"], "name": u["name"] + " (T11)"}, tok,
           {"Idempotency-Key": "t11-rename-" + unit})
print(json.dumps({"unit": unit, "name": out.get("name"), "version": out.get("version")}))
PY
UNIT_VERSION=$(sql "select version from mdm_org.org_unit where id = '$RENAMED'")
step rename-published until_sql "select count(*) from mdm_org.be_outbox where record_id = '$RENAMED' and version = $UNIT_VERSION and published_at is not null" 30
step backdate sql "update mdm_org.be_outbox set occurred_at = occurred_at - interval '2 days', published_at = published_at - interval '2 days' where record_id = '$RENAMED' and version = $UNIT_VERSION returning event_id"
RENAME_EVENT=$(grep -oE '[0-9a-f-]{36}' $O/backdate.log | head -1)
echo "scenario 3: unit $RENAMED renamed (version $UNIT_VERSION, event $RENAME_EVENT) while sales is down; dated two days back" >> $O/summary.txt
counts > $O/counts-T.txt; sleep 2; T=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ); sleep 2
echo "T=$T" >> $O/summary.txt
step sales-start docker start $SALES
step sales-caught-up until_sql "select count(*) from erp_sales.be_inbox where event_id = '$RENAME_EVENT'" 120
step after-T env FROM=scenarios KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh R4-G $O/cell-after
# scenarios 2 and 6 after T: a revocation, a disablement, a retirement, a second factor reset; a password changed in
# Casdoor by an authorization admin (test.unit.admin.cn)
export GRANT UNIT
GRANT=$(sql "select id from infra_authz.authz_record where record_type = 'grant' and state = 'active' and body->>'grantee' = '$VIEWER' order by created_at, id limit 1")
UNIT=$(sql "select u.id from mdm_org.org_unit u join mdm_org.legal_entity e on e.id = u.legal_entity_id where e.code = 'US01' and u.state = 'active' and not exists (select 1 from mdm_org.org_unit c where c.parent_id = u.id) order by u.code limit 1")
echo "after T: revoke $GRANT, disable test.revoked, retire $UNIT, reset test.mdm.viewer's second factor" >> $O/summary.txt
step after-T-tighten $T_TOOL after
NEW_PW="T11-$(openssl rand -hex 6)-Aa1"
step password-in-casdoor env NEW_PASSWORD="$NEW_PW" $C password test.unit.admin.cn
step password-seen until_sql "$(evidence_of credential_tightening_in_product general $ADMINCN)" 150
step reset-seen until_sql "$(evidence_of credential_tightening effective $VIEWER)" 30
step pay-after $P pay r-after
step pay-after-final $P wait r-after succeeded
step pay-pending-final $P wait r-pending succeeded  # its retry went out after T
step pay-stale-still $P wait r-stale retry_wait
# scenarios 4 and 5, then the failure: the shell killed while the evidence store is paused
step intent-only $T_TOOL intent-only
step alert-only $T_TOOL alert-only
step crash docker kill $SHELL_C
FAILED_AT=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ); echo "failed at $FAILED_AT" >> $O/summary.txt
step store-back docker unpause $AUDIT_CONTAINER
# scenario 5: the intent in the alert channel (the run profile's alert records of this deployment, P12.16)
S3U="$(val STORAGE_ACCESS_KEY):$(val STORAGE_SECRET_KEY)"
alerts=$(curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile?list-type=2&prefix=$DEP/alert/" | grep -o "<Key>[^<]*</Key>" | sed 's/<[^>]*>//g')
mkdir -p $O/alerts; for k in $alerts; do curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile/$k" -o $O/alerts/$(basename $k); done
echo "CHECK scenario 5, the alert channel holds test.rates' intent: $(grep -l "$RATES" $O/alerts/*.json 2>/dev/null | wc -l) (1)" >> $O/summary.txt
echo "CHECK intent-only in the store: intent $(sql "$(evidence_of account_status intent $EXPIRED)"), conclusion $(sql "$(evidence_of account_status effective $EXPIRED)") (1, 0)" >> $O/summary.txt
echo "CHECK alert-only in the store: intent $(sql "$(evidence_of account_status intent $RATES)"), conclusion $(sql "$(evidence_of account_status effective $RATES)") (0, 0)" >> $O/summary.txt
counts > $O/counts-after.txt
export RUN_PROFILE_URL=http://localhost:9000 RUN_PROFILE_BUCKET=be-run-profile RUN_PROFILE_ACCESS_KEY=$(val STORAGE_ACCESS_KEY) \
  RUN_PROFILE_SECRET_KEY=$(val STORAGE_SECRET_KEY) SERVICE_TLS_CERT_FILE=$D/.secrets/tls/ops-recover.cert.pem \
  SERVICE_TLS_KEY_FILE=$D/.secrets/tls/ops-recover.key.pem SERVICE_TLS_CA_FILE=$D/.secrets/tls/ca.pem \
  RECOVER_PG_ADMIN="postgres://postgres:$PW@localhost:5432/postgres?sslmode=disable" BUS_URL=nats://localhost:4222
B="$BIN/be-ops recover"
RT0=$(ms)
step announce $B announce --project $D --reason "T11 drill: the gate, protocol 15's drill scenarios" --approver "T11" --at "$T"
step freeze $B freeze --project $D
step restore-db $B restore-db --project $D
echo "CHECK scenario 3 right after the restore: sales has the rename event: $(sql "select count(*) from erp_sales.be_inbox where event_id = '$RENAME_EVENT'") (0: behind at T)" >> $O/summary.txt
step advance $B advance --project $D
step redeliver $B redeliver --project $D
$B status --project $D > $O/status.txt 2>&1
counts > $O/counts-restored.txt
KEY_BEFORE=$(sha256sum $D/.secrets/iam/signing-key.pem | cut -c1-16)
step replay $B replay --project $D
step keys $B keys --project $D
rec=$(curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile?list-type=2&prefix=$DEP/recovery.step/" | grep -o "<Key>[^<]*</Key>" | sed 's/<[^>]*>//g')
mkdir -p $O/run-profile; for k in $rec; do curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile/$k" -o $O/run-profile/$(basename $k); done
python3 - $O/run-profile > $O/replay-review.txt <<'PY'
import json, pathlib, sys
for f in sorted(pathlib.Path(sys.argv[1]).glob('*.json')):
    b = json.loads(f.read_text()).get('body', {})
    if b.get('step') != 'replay':
        continue
    rep = b['detail']['report']
    print('alerts_untrusted', b['detail'].get('alerts_untrusted'))
    for o in rep['outcomes']:
        if o['outcome'] != 'reflected' or o.get('intent_only'):
            print(o['owner'], o['category'], o['phase'], o['outcome'], 'intent_only' if o.get('intent_only') else '', o.get('detail', '')[:120])
    print('review', len(rep.get('review') or []))
PY
sed 's/^/CHECK replay outcome: /' $O/replay-review.txt >> $O/summary.txt
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
{
echo "CHECK scenario 2, the revoked grant: $(sql "select state from infra_authz.authz_record where id = '$GRANT'") (ended)"
echo "CHECK test.revoked: $(sql "select status from infra_iam_casdoor.iam_account where username = 'brickkit/test.revoked'") (disabled)"
echo "CHECK scenario 4, test.expired (intent only): $(sql "select status from infra_iam_casdoor.iam_account where principal = '$EXPIRED'") (disabled)"
echo "CHECK scenario 5, test.rates (alert channel only): $(sql "select status from infra_iam_casdoor.iam_account where principal = '$RATES'") (disabled)"
echo "CHECK the retired unit: $(sql "select state from mdm_org.org_unit where id = '$UNIT'") (retired)"
echo "CHECK live sessions from before: $(sql "select count(*) from infra_iam_casdoor.iam_session where ended_at is null and recovery_generation < (select generation from infra_iam_casdoor.be_recovery_generation)") (0)"
echo "CHECK the authorization state: $(sql "select admin_state from infra_authz.authz_state") (operational)"
echo "CHECK the signing key: $KEY_BEFORE -> $(sha256sum $D/.secrets/iam/signing-key.pem | cut -c1-16) (another)"
echo "CHECK scenario 3, sales has the rename event again: $(sql "select count(*) from erp_sales.be_inbox where event_id = '$RENAME_EVENT'") (1); its unit at version $(sql "select version from erp_sales.be_projection where record_id = '$RENAMED'") ($UNIT_VERSION)"
grep -E '^replayed:|⚠|alert' $O/replay.log | sed 's/^/CHECK replay: /'
} >> $O/summary.txt
step reconcile $B reconcile --project $D --window 1h --failed-at "$FAILED_AT"
step check $B check --project $D
step loss $B loss --project $D
step open-read $B open-read --project $D --approver "T11" --reason "T11 drill: the differences the check lists are read in the report"
# scenario 6: the authorization admin whose password changed in Casdoor after T signs in with the new one, not the old
python3 -I - > $O/sign-in.log 2>&1 <<PY
import json, os, urllib.request, urllib.error
def code(pw):
    req = urllib.request.Request(os.environ["IAM_URL"] + "/api/iam/dev/token", method="POST",
        data=json.dumps({"username": "test.unit.admin.cn", "password": pw}).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status
    except urllib.error.HTTPError as e: return e.code
print("new", code("$NEW_PW"), "old", code(os.environ["BE_ACC_IAM_TEST_PASSWORD"]))
PY
echo "CHECK scenario 6, test.unit.admin.cn in read_only: $(cat $O/sign-in.log) (new 200, old 401)" >> $O/summary.txt
step open $B open --project $D --approver "T11"
RT=$(( $(ms) - RT0 ))
$B status --project $D > $O/status-end.txt 2>&1
{
echo "CHECK the state: $(grep '^state:' $O/status-end.txt) (running)"
echo "CHECK the recovery took $RT ms from the announcement to running"
echo "CHECK scenario 1, r-pending at the probe: $($P state r-pending) (succeeded), taken by the fake: $($P taken r-pending) (1)"
echo "CHECK scenarios 1 and 7, r-after at the probe: $($P state r-after) (none: lost with the recovery), taken: $($P taken r-after) (1)"
echo "CHECK scenario 8, r-stale at the probe: $($P state r-stale) (manual or unknown, never resent), taken: $($P taken r-stale) (0); first sent at $STALE_FIRST"
echo "CHECK voided invoice numbers: $(sql "select count(*) from erp_billing.voided_number") (as many as the invoices issued after T)"
grep -E '^reconciled|^checked|^the loss|^number series|open for reading|r-stale|r-pending|r-after' $O/reconcile.log $O/check.log $O/loss.log $O/open-read.log $O/open.log | sed 's/^/CHECK /'
grep -E 'credential|consistent' $O/replay.log | head -8 | sed 's/^/CHECK 6.7: /'
} >> $O/summary.txt
# each payment's conclusion at the reconciliation (the run profile's record of step 7)
rec=$(curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile?list-type=2&prefix=$DEP/recovery.step/" | grep -o "<Key>[^<]*</Key>" | sed 's/<[^>]*>//g')
for k in $rec; do curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile/$k" -o $O/run-profile/$(basename $k); done
python3 - $O/run-profile <<'PY' >> $O/summary.txt
import json, pathlib, sys
for f in sorted(pathlib.Path(sys.argv[1]).glob('*.json')):
    b = json.loads(f.read_text()).get('body', {})
    if b.get('step') == 'reconcile':
        for comp, cs in b['detail']['conclusions'].items():
            for c in cs:
                print(f"CHECK reconcile {comp} {c['reference']}: {c['conclusion']} {c.get('state', '')} {c.get('resend_deadline', '')}")
PY
echo "CHECK expected: r-pending matched (scenario 1), r-after external_only (scenario 7), r-stale past its deadline: unknown or manual, not resent (scenario 8)" >> $O/summary.txt
step scenarios-again env FROM=scenarios KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh R4-G $O/cell-again
bash $R/dev/rebuild/experiment-scripts/cell-logs.sh $D $O/logs > /dev/null 2>&1
(cd $D && brickkit down > /dev/null 2>&1)
bash $R/infra/scripts/pg-backup.sh off >> $O/summary.txt 2>&1
(cd $R/components/infra/iam-casdoor && CASDOOR_URL=$CASDOOR_URL CASDOOR_ADMIN_PASSWORD=$CASDOOR_ADMIN_PASSWORD \
  IAM_TEST_PASSWORD=$(val IAM_TEST_PASSWORD) python3 -I scripts/dev_setup.py --users-only > /dev/null 2>&1) && echo "test accounts reset in Casdoor" >> $O/summary.txt
NEW_PASSWORD=$(val IAM_TEST_PASSWORD) $C password test.unit.admin.cn > /dev/null 2>&1 && echo "test.unit.admin.cn's password set back" >> $O/summary.txt
echo "T11 ALL-DONE" >> $O/summary.txt
