#!/bin/bash
# Foundations item 6, T11: a full recovery with the Python members taking part (gate F4). Steps 1-10 of be-ops recover
# (protocol 15) on the cell T6-R: be/go-infra and be/go-core as in T6-H, be/py-render hosting infra/print and the
# Python probe py2, which pays into the suite's fake payment system (port 18990). Before T: the chain to L3 (print
# renders the invoices; it keeps no record of a rendering, only its templates), a payment r-before. After T: the L3
# scenarios again, a payment r-after and a write of the probe (a row of its own table, gone with the recovery). The failure: the Python shell killed. Then every step; after each phase change every member
# reports the phase and none is stopped ("stopped while the recovery runs" never appears); while frozen the Python
# members answer MAINTENANCE on the user surface; step 7 reconciles the probe's payments (r-after external only: lost
# with the recovery; r-before had succeeded before T, nothing to reconcile), step 8 has print's and the probe's checks pass; the tables are back at T;
# after the opening the L3 scenarios run again. Output: this directory, summary.txt ("T11 DRILL ALL-DONE" last).
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")/drill; D=$R/dev/rebuild/experiment-cells/T6-R
mkdir -p $O; echo $$ > $O/run.pid; : > $O/summary.txt
. $R/dev/rebuild/experiment-scripts/cellenv.sh  # PW, BE_ACC_*, Casdoor's client secrets, build_be_ops, recover_env (P3)
val() { envval "$@"; }
sql() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_experiment -Atc "$1"; }
ms() { date -u +%s%3N; }
done_mark() { echo "T11 DRILL ALL-DONE" >> $O/summary.txt; }
step() { local name=$1; shift; local t0; t0=$(ms); echo "DRILL $name BEGIN $(date -u +%H:%M:%S)" >> $O/summary.txt
  "$@" > $O/$name.log 2>&1; local rc=$?; echo "DRILL $name END rc=$rc $(( $(ms) - t0 )) ms" >> $O/summary.txt
  if [ $rc -ne 0 ]; then echo "DRILL FAILED $name" >> $O/summary.txt; left_up; exit 1; fi; }
counts() {
  sql "SELECT table_schema || '.' || table_name || ' ' ||
    (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text
    FROM information_schema.tables WHERE table_type = 'BASE TABLE' AND table_schema IN
    (SELECT schema_name FROM information_schema.schemata WHERE schema_name ~ '^(infra|mdm|erp|test)_') AND table_name !~ '^be_'
    ORDER BY 1"; }
container() { docker ps -a --filter label=com.docker.compose.project=brickkit-t6-r --format '{{.Names}}' | grep -- "$1" | head -1; }
# a phase step's log: every member reported the phase, none stopped
phase_ok() { grep -q 'every member reports the phase' $O/$1.log && ! grep -q 'stopped while the recovery runs' $O/$1.log; }
# the Python members' user surface while frozen: the probe's echo and print's templates answer MAINTENANCE
bob_token() { python3 -I -c "
import json, os, urllib.request
r = urllib.request.Request(os.environ['IAM_URL'] + '/api/iam/dev/token', method='POST', headers={'Content-Type': 'application/json'},
    data=json.dumps({'username': 'test.bob', 'password': os.environ['BE_ACC_IAM_TEST_PASSWORD']}).encode())
print(json.load(urllib.request.urlopen(r, timeout=10))['access_token'])"; }
maintenance() { local tok=$TOK p q  # taken before the freeze: the identity member answers MAINTENANCE too
  p=$(curl -s -X POST -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -H 'X-Requested-With: t11' \
    -d '{"payload":"x"}' http://localhost:18605/api/probe/echo); q=$(curl -s -H "Authorization: Bearer $tok" http://localhost:$PRINT_PORT/api/print/templates)
  echo "probe: $p"; echo "print: $q"
  echo "$p" | grep -q MAINTENANCE && echo "$q" | grep -q MAINTENANCE; }
finish() {
  bash $R/dev/rebuild/experiment-scripts/cell-logs.sh $D $O/logs > /dev/null 2>&1
  (cd $D && brickkit down > /dev/null 2>&1)
  kill ${FAKE:-} 2>/dev/null
  bash $R/infra/scripts/pg-backup.sh off >> $O/summary.txt 2>&1
  done_mark; }
# a failed drill leaves the cell, the WAL archive and the recovery's state as they are, for the look at them (P4); the
# deployment is a new one every drill, so the next drill starts afresh. DOWN=1 stops everything anyway.
left_up() {
  [ "${DOWN:-}" = 1 ] && { finish; return; }
  bash $R/dev/rebuild/experiment-scripts/cell-logs.sh $D $O/logs > /dev/null 2>&1
  kill ${FAKE:-} 2>/dev/null
  echo "left up: the cell T6-R and the WAL archive; stop with (cd $D && brickkit down) and bash $R/infra/scripts/pg-backup.sh off" >> $O/summary.txt
  done_mark; }

DEP=$(python3 -c 'import os, time, uuid; b = bytearray(int(time.time() * 1000).to_bytes(6, "big") + os.urandom(10)); b[6] = b[6] & 0x0F | 0x70; b[8] = b[8] & 0x3F | 0x80; print(uuid.UUID(bytes=bytes(b)))')
sed -i "s/^deployment: .*/deployment: $DEP/" $D/cell.yaml
code=$(curl -s -o /dev/null -w '%{http_code}' --aws-sigv4 "aws:amz:us-east-1:s3" --user "$(val STORAGE_ACCESS_KEY):$(val STORAGE_SECRET_KEY)" \
  -X PUT -H 'x-amz-bucket-object-lock-enabled: true' http://localhost:9000/be-run-profile)
echo "run profile bucket: HTTP $code (200 made, 409 there); deployment $DEP" >> $O/summary.txt
BIN=$(mktemp -d)  # be-ops built from source, outside the repository; static: the calls run in alpine
build_be_ops $BIN || { echo "DRILL FAILED be-ops build" >> $O/summary.txt; done_mark; exit 1; }
export IAM_URL=http://localhost:18200
export PYTHONDONTWRITEBYTECODE=1
python3 -I $R/tools/be-acceptance/conformance/external/fake.py --port 18990 > $O/fake.log 2>&1 &
FAKE=$!
P="python3 -I $O/../pay.py"
for c in T6-S T6-H T6-R; do (cd $R/dev/rebuild/experiment-cells/$c && brickkit down > /dev/null 2>&1); done
step archive bash $R/infra/scripts/pg-backup.sh on
step cell env KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh T6-R $O/cell
PY=$(container py-render); echo "Python shell: $PY" >> $O/summary.txt
PRINT_PORT=$(python3 -c "import yaml; d = yaml.safe_load(open('$D/deploy.yaml'))
print(next(m['exposePort'] for c in d['components'] for m in c.get('members') or [] if m['id'] == 'infra/print'))")
step pay-before $P pay r-before
step pay-before-final $P wait r-before succeeded
counts > $O/counts-T.txt; sleep 2; T=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ); sleep 2
echo "T=$T" >> $O/summary.txt
step after-T env FROM=scenarios KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh T6-R $O/cell-after
step pay-after $P pay r-after
step pay-after-final $P wait r-after succeeded
step probe-write python3 -I -c "
import json, os, urllib.request
def post(url, body, tok=None):
    r = urllib.request.Request(url, method='POST', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json',
        'X-Requested-With': 't11', **({'Authorization': 'Bearer ' + tok} if tok else {})})
    return json.load(urllib.request.urlopen(r, timeout=10))
tok = post(os.environ['IAM_URL'] + '/api/iam/dev/token', {'username': 'test.bob', 'password': os.environ['BE_ACC_IAM_TEST_PASSWORD']})['access_token']
print(post('http://localhost:18605/api/probe/write', {'bytes': 10}, tok))"
counts > $O/counts-after.txt
step crash docker kill $PY
FAILED_AT=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ); echo "the failure at $FAILED_AT (the Python shell killed)" >> $O/summary.txt
recover_env $D
B="$BIN/be-ops recover"
TOK=$(bob_token)
RT0=$(ms)
step announce $B announce --project $D --reason "T11 drill: the Python members take part (gate F4)" --approver "T11" --at "$T"
step freeze $B freeze --project $D
step freeze-phase phase_ok freeze
step maintenance maintenance
step restore-db $B restore-db --project $D
step advance $B advance --project $D
step redeliver $B redeliver --project $D
counts > $O/counts-restored.txt
step replay $B replay --project $D
step keys $B keys --project $D
step reconcile $B reconcile --project $D --window 1h --failed-at "$FAILED_AT"
step check $B check --project $D
step loss $B loss --project $D
step open-read $B open-read --project $D --approver "T11" --reason "T11 drill: the differences the check lists are read in the report"
step open $B open --project $D --approver "T11"
RT=$(( $(ms) - RT0 ))
$B status --project $D > $O/status-end.txt 2>&1
for s in freeze restore-db advance redeliver replay open-read open; do
  echo "CHECK $s: $(grep -E 'every member reports the phase|stopped while' $O/$s.log | tr '\n' ' ')" >> $O/summary.txt; done
python3 - $O <<'PY' >> $O/summary.txt
import sys, pathlib
o = pathlib.Path(sys.argv[1])
read = lambda n: dict(l.rsplit(' ', 1) for l in (o / n).read_text().split('\n') if l.strip())
t, after, back = read('counts-T.txt'), read('counts-after.txt'), read('counts-restored.txt')
moved = [k for k in t if not k.startswith('infra_audit.') and after.get(k) != t[k]]
wrong = [f"{k}: T {t[k]}, restored {back.get(k)}" for k in t if not k.startswith('infra_audit.') and back.get(k) != t[k]]
py = [k for k in moved if k.startswith(('infra_print.', 'test_probe_py2.'))]
print(f"CHECK tables that changed after T: {len(moved)}, the Python members' {len(py)} ({', '.join(py)})")
print(f"CHECK tables not back at T: {len(wrong)} {wrong[:8]}")
PY
S3U="$(val STORAGE_ACCESS_KEY):$(val STORAGE_SECRET_KEY)"
rec=$(curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile?list-type=2&prefix=$DEP/recovery.step/" | grep -o "<Key>[^<]*</Key>" | sed 's/<[^>]*>//g')
mkdir -p $O/run-profile; for k in $rec; do curl -s --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3U" "http://localhost:9000/be-run-profile/$k" -o $O/run-profile/$(basename $k); done
python3 - $O/run-profile <<'PY' >> $O/summary.txt
import json, pathlib, sys
for f in sorted(pathlib.Path(sys.argv[1]).glob('*.json')):
    b = json.loads(f.read_text()).get('body', {})
    if b.get('step') == 'reconcile':
        for comp, cs in b['detail']['report']['conclusions'].items():
            for c in cs:
                print(f"CHECK reconcile {comp} {c['reference']}: {c['conclusion']} {c.get('state', '')}")
    if b.get('step') == 'check':
        rep = b['detail'].get('report') or b['detail']
        for comp, cs in (rep.get('checks') or {}).items():
            if comp in ('infra/print', 'test/probe-py2'):
                for c in cs:
                    print(f"CHECK step 8 {comp} {c['check']}: {c['outcome']} {(c.get('detail') or '')[:100]}")
PY
{
echo "CHECK the state: $(grep '^state:' $O/status-end.txt) (running)"
echo "CHECK the recovery took $RT ms from the announcement to running"
echo "CHECK r-before at the probe: $($P state r-before) (succeeded), taken by the fake: $($P taken r-before) (1)"
echo "CHECK r-after at the probe: $($P state r-after) (none: lost with the recovery), taken: $($P taken r-after) (1)"
echo "CHECK print's templates now: $(sql "select count(*) || ' templates, ' || (select count(*) from infra_print.template_version) || ' versions' from infra_print.template") (as at T: $(grep '^infra_print' $O/counts-T.txt | tr '\n' ' '))"
echo "CHECK expected: every phase reported by every member, none stopped; r-after external_only (r-before final before T: not listed); print's and the probe's checks pass"
} >> $O/summary.txt
step scenarios-again env FROM=scenarios KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh T6-R $O/cell-again
finish
