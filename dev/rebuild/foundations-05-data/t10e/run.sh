#!/bin/bash
# Foundations item 5, T10e: the tiering in real cells, every member alone (T5-S) and in shells (T5-H), each from an
# empty database (suite 1.0.63; be-sdk-go alpha.115 everywhere; be/go-infra and be/go-core 3.0.64):
#   chain     cell-chain.sh: create, prepare, build, up, secure, seeds twice, L3; a new deployment for the run
#   backdate  the ended orders' updated_at 400 days back (and their creation 420: a unit is released only once its newest
#             record is N days old, TR25), the audit records' received_at 800 days back (past the residence of 365
#             days: the candidates job, every minute here, seals them)
#   before    tier.py: test.bob may read the audit records; the probe's archives (closed 400 days ago, open); the reads
#   published every class's units sealed, copied and published (the transfer job, every minute); the reads again
#   backup    be-ops recover backup-record: a backup that finished after the publishes (P15.21); the release job
#             (hourly) made due at once
#   released  the units released, their online rows gone; the reads again; the audit chain check has run since
#   check     the recovery check be.tiering (P15.36) of the members with classes, through be-ops recover verify-calls
#             in the deployment's network with the ops/recover certificate (the check service answers in any phase)
# Then the cell's logs and down. Output: <cell>/ per cell, summary.txt ("T10E ALL-DONE" last).
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/run.pid; : > $O/summary.txt
E=$R/.env; val() { grep "^$1=" $E | cut -d= -f2- | tr -d "\"'"; }
PW=$(val POSTGRES_PASSWORD)
sql() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_experiment -Atc "$1"; }
export BE_ACC_IAM_TEST_PASSWORD; BE_ACC_IAM_TEST_PASSWORD=$(val IAM_TEST_PASSWORD)
BIN=$(mktemp -d)  # be-ops built from source, outside the repository (no build output in it); left in /tmp
(cd $R/tools/be-ops && CGO_ENABLED=0 go build -o $BIN/be-ops ./cmd/be-ops) || { echo "be-ops build failed" >> $O/summary.txt; echo "T10E ALL-DONE" >> $O/summary.txt; exit 1; }
export BE_OPS=$BIN/be-ops  # a secured cell's certificates come from its issuer (prepare.py)
TIER="uv run --project $R/tools/be-acceptance/conformance python $O/tier.py"
export PYTHONDONTWRITEBYTECODE=1
# until every class's units are in state $2 and none is before it (schemas in $1), at most $3 seconds
until_units() { local schemas=$1 want=$2 n=$3 s ok
  for _ in $(seq 1 "$n"); do ok=1
    for s in $schemas; do
      [ "$(sql "SELECT count(*) FROM $s.be_tier_unit WHERE state = '$want'")" -gt 0 ] || ok=0
      [ "$(sql "SELECT count(*) FROM $s.be_tier_unit WHERE state IN ('open', 'sealed'$( [ $want = released ] && echo ", 'published'"))")" -eq 0 ] || ok=0
    done
    [ $ok = 1 ] && return 0; sleep 1; done
  for s in $schemas; do echo "$s: $(sql "SELECT string_agg(state || ' ' || n, ', ') FROM (SELECT state, count(*) n FROM $s.be_tier_unit GROUP BY 1) x")"; done
  return 1; }
for C in ${CELLS:-T5-S T5-H}; do
  D=$R/dev/rebuild/experiment-cells/$C; OC=$O/$C; mkdir -p $OC; lc=$(echo $C | tr 'A-Z' 'a-z')
  step() { local name=$1; shift; local t0; t0=$(date +%s); echo "$C $name BEGIN $(date -u +%H:%M:%S)" >> $O/summary.txt
    "$@" > $OC/$name.log 2>&1; local rc=$?; echo "$C $name END rc=$rc $(( $(date +%s) - t0 )) s" >> $O/summary.txt
    [ $rc -eq 0 ] || echo "$C FAILED $name" >> $O/summary.txt; return $rc; }
  DEP=$(python3 -c 'import os, time, uuid; b = bytearray(int(time.time() * 1000).to_bytes(6, "big") + os.urandom(10)); b[6] = b[6] & 0x0F | 0x70; b[8] = b[8] & 0x3F | 0x80; print(uuid.UUID(bytes=bytes(b)))')
  sed -i "s/^deployment: .*/deployment: $DEP/" $D/cell.yaml
  PROBE=$(grep -o 'test/probe-go2\?' $D/cell.yaml | head -1); PS=$(echo $PROBE | tr '/-' '__')
  SCHEMAS="infra_audit erp_sales $PS"
  run() {
    step chain env KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh $C $OC/chain || return 1
    step backdate sql "UPDATE erp_sales.sales_order SET updated_at = now() - interval '400 days', created_at = now() - interval '420 days'
      WHERE state IN ('completed', 'cancelled');
      UPDATE infra_audit.audit_record SET received_at = now() - interval '800 days'" || return 1
    step before $TIER before $D $OC || return 1  # after the backdate: the dates are part of what is read
    step units-published until_units "$SCHEMAS" published 600 || return 1
    sql "SELECT 'erp_sales ' || state || ' ' || count(*) FROM erp_sales.be_tier_unit GROUP BY state UNION ALL
         SELECT 'infra_audit ' || state || ' ' || count(*) FROM infra_audit.be_tier_unit GROUP BY state UNION ALL
         SELECT '$PS ' || state || ' ' || route || ' ' || count(*) FROM $PS.be_tier_unit GROUP BY state, route" > $OC/units-published.txt
    step published $TIER compare $D $OC published || return 1
    step backup env RUN_PROFILE_URL=http://localhost:9000 RUN_PROFILE_BUCKET=be-run-profile \
      RUN_PROFILE_ACCESS_KEY="$(val STORAGE_ACCESS_KEY)" RUN_PROFILE_SECRET_KEY="$(val STORAGE_SECRET_KEY)" \
      SERVICE_TLS_CERT_FILE=$D/.secrets/tls/ops-recover.cert.pem SERVICE_TLS_KEY_FILE=$D/.secrets/tls/ops-recover.key.pem \
      SERVICE_TLS_CA_FILE=$D/.secrets/tls/ca.pem BUS_URL=nats://localhost:4222 \
      RECOVER_PG_ADMIN="postgres://postgres:$PW@localhost:5432/postgres?sslmode=disable" \
      $BIN/be-ops recover backup-record --project $D --backup "t10e-$lc" --finished-at "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" || return 1
    for s in $SCHEMAS; do sql "UPDATE $s.be_work_item SET run_at = now() WHERE id = 'be.tiering.release' AND state = 'pending'"; done
    step units-released until_units "$SCHEMAS" released 300 || return 1
    step online-rows sql "SELECT 'erp_sales.sales_order dated back ' || count(*) FROM erp_sales.sales_order WHERE updated_at < now() - interval '300 days'
      UNION ALL SELECT 'infra_audit.audit_record dated back ' || count(*) FROM infra_audit.audit_record WHERE received_at < now() - interval '700 days'
      UNION ALL SELECT '$PS.probe_archive closed ' || count(*) FROM $PS.probe_archive WHERE closed_at IS NOT NULL" || return 1
    grep -q ' 0$' $OC/online-rows.log && [ "$(grep -c ' 0$' $OC/online-rows.log)" = 3 ] || { echo "$C FAILED online rows left" >> $O/summary.txt; return 1; }
    step released $TIER compare $D $OC released || return 1
    sleep 45  # the audit chain check runs every 20 s here: twice since the release
    step chain-breaks sql "SELECT count(*) FROM infra_audit.audit_chain_break" || return 1
    [ "$(cat $OC/chain-breaks.log)" = 0 ] || { echo "$C FAILED audit chain breaks" >> $O/summary.txt; return 1; }
    step checkin $TIER checkin $D $OC || return 1
    step check docker run --rm --network brickkit-$lc-net --user "$(id -u)" -v $BIN/be-ops:/be-ops:ro -v $OC:/work \
      -v $D/.secrets/tls/ops-recover.cert.pem:/certs/cert.pem:ro -v $D/.secrets/tls/ops-recover.key.pem:/certs/key.pem:ro \
      -v $D/.secrets/tls/ca.pem:/certs/ca.pem:ro -e SERVICE_TLS_CERT_FILE=/certs/cert.pem -e SERVICE_TLS_KEY_FILE=/certs/key.pem \
      -e SERVICE_TLS_CA_FILE=/certs/ca.pem -e DEPLOYMENT_ID=$DEP alpine:3.24.2 /be-ops recover verify-calls \
      --in /work/check-in.json --out /work/check-out.json || return 1
    step check-tiering python3 -c "
import json, sys
rep = json.load(open('$OC/check-out.json'))
bad = 0
for m in json.load(open('$OC/check-in.json'))['members']:
    got = [c for c in (rep.get('checks') or {}).get(m, []) if c['check'] == 'be.tiering']
    print(m, got)
    bad += not got or got[0]['outcome'] != 'pass'
print('failed', rep.get('failed'), 'unimplemented', rep.get('unimplemented'))
sys.exit(1 if bad or rep.get('failed') else 0)" || return 1
  }
  run; rc=$?
  echo "$C rc=$rc" >> $O/summary.txt
  bash $R/dev/rebuild/experiment-scripts/cell-logs.sh $D $OC/containers D > /dev/null 2>&1
  for n in $(docker ps -a --format '{{.Names}}' | grep "brickkit-$lc-"); do
    docker logs $n 2>&1 | grep -iE 'tier|"level":"(ERROR|WARN)"' | tail -200 > $OC/containers/$n.tiering.log; done
  (cd $D && brickkit down > /dev/null 2>&1)
  [ $rc -eq 0 ] || break  # the next cell would meet the same problem
done
echo "T10E ALL-DONE" >> $O/summary.txt
