#!/bin/bash
# Foundations item 6, T11: the Python members in real cells, every member alone (T6-S) and in shells (T6-H), each from
# an empty database (suite 1.0.75; be-sdk-go alpha.119 and be-sdk-python a61 everywhere; be/py-render 3.0.51):
#   chain     cell-chain.sh: create, prepare, build, up, secure, seeds twice, L3 (infra/print renders the invoices); a
#             new deployment for the run
#   before    tier.py: the Python probe's archives (closed 400 days ago, open); the reads
#   published the closed archive's unit sealed, copied and published (the probe's own jobs, every minute); the reads
#   backup    be-ops recover backup-record: a backup that finished after the publish (P15.21); the release job (hourly)
#             made due at once
#   released  the unit released, its online rows gone; the reads again
#   check     the recovery checks (CheckService, P14.1) of infra/print and the probe, through be-ops recover verify-calls
#             in the deployment's network with the ops/recover certificate: every check passes, the probe's be.tiering
#   profile   the suite's core profile of the probe and the shells (cells profile; it stops the cell)
# Then the cell's logs and down. Output: <cell>/ per cell, summary.txt ("T11 ALL-DONE" last).
# CELLS picks the cells (T6-S T6-H); FROM=<stage> resumes the first cell at that stage (its deployment kept). A failed
# cell stays up (retrospective 6, P4), the summary's last lines say how to resume or stop it; DOWN=1 stops it anyway.
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/run.pid; [ -n "${FROM:-}" ] || : > $O/summary.txt
. $R/dev/rebuild/experiment-scripts/cellenv.sh  # PW, BE_ACC_*, build_be_ops, recover_env (retrospective 6, P3)
sql() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_experiment -Atc "$1"; }
BIN=$(mktemp -d)  # be-ops built from source, outside the repository (no build output in it); left in /tmp
build_be_ops $BIN || { echo "be-ops build failed" >> $O/summary.txt; echo "T11 ALL-DONE" >> $O/summary.txt; exit 1; }
CONF=$R/tools/be-acceptance/conformance
TIER="uv run --project $CONF python $O/tier.py"
export PYTHONDONTWRITEBYTECODE=1
# until the schema's units include one in state $2 and none before it, at most $3 seconds
until_units() { local s=$1 want=$2 n=$3
  for _ in $(seq 1 "$n"); do
    [ "$(sql "SELECT count(*) FROM $s.be_tier_unit WHERE state = '$want'")" -gt 0 ] &&
      [ "$(sql "SELECT count(*) FROM $s.be_tier_unit WHERE state IN ('open', 'sealed'$( [ $want = released ] && echo ", 'published'"))")" -eq 0 ] && return 0
    sleep 1; done
  echo "$s: $(sql "SELECT string_agg(state || ' ' || n, ', ') FROM (SELECT state, count(*) n FROM $s.be_tier_unit GROUP BY 1) x")"
  return 1; }
for C in ${CELLS:-T6-S T6-H}; do
  D=$R/dev/rebuild/experiment-cells/$C; OC=$O/$C; mkdir -p $OC; lc=$(echo $C | tr 'A-Z' 'a-z')
  step() { local name=$1; shift; local t0; t0=$(date +%s); echo "$C $name BEGIN $(date -u +%H:%M:%S)" >> $O/summary.txt
    "$@" > $OC/$name.log 2>&1; local rc=$?; echo "$C $name END rc=$rc $(( $(date +%s) - t0 )) s" >> $O/summary.txt
    [ $rc -eq 0 ] || echo "$C FAILED $name" >> $O/summary.txt; return $rc; }
  if [ -z "${FROM:-}" ]; then
    DEP=$(python3 -c 'import os, time, uuid; b = bytearray(int(time.time() * 1000).to_bytes(6, "big") + os.urandom(10)); b[6] = b[6] & 0x0F | 0x70; b[8] = b[8] & 0x3F | 0x80; print(uuid.UUID(bytes=bytes(b)))')
    sed -i "s/^deployment: .*/deployment: $DEP/" $D/cell.yaml
  fi
  DEP=$(sed -n 's/^deployment: //p' $D/cell.yaml)
  PROBE=$(grep -o 'test/probe-py2\?' $D/cell.yaml | head -1); PS=$(echo $PROBE | tr '/-' '__')
  STAGES="chain before units-published published backup units-released online-rows released checkin check check-result profile"
  todo() { [ -z "${FROM:-}" ] && return 0; case " $STAGES " in *" $FROM "*) ;; *) return 0 ;; esac
    local s; for s in $STAGES; do [ "$s" = "$FROM" ] && return 0; [ "$s" = "$1" ] && return 1; done; }
  with_recover() { ( recover_env $D; "$@" ); }  # be-ops recover's environment for this cell only
  run() {
    todo chain && { step chain env KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh $C $OC/chain || return 1; }
    todo before && { step before $TIER before $D $OC || return 1; }
    todo units-published && { step units-published until_units $PS published 600 || return 1; }
    todo published && { step published $TIER compare $D $OC published || return 1; }
    sql "SELECT state || ' ' || route || ' ' || count(*) FROM $PS.be_tier_unit GROUP BY state, route" > $OC/units.txt
    todo backup && { step backup with_recover $BIN/be-ops recover backup-record --project $D --backup "t11-$lc" --finished-at "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" || return 1
      sql "UPDATE $PS.be_work_item SET run_at = now() WHERE id = 'be.tiering.release' AND state = 'pending'"; }
    todo units-released && { step units-released until_units $PS released 300 || return 1; }
    todo online-rows && { step online-rows sql "SELECT count(*) FROM $PS.probe_archive WHERE closed_at IS NOT NULL" || return 1
      [ "$(cat $OC/online-rows.log)" = 0 ] || { echo "$C FAILED closed archives still online" >> $O/summary.txt; return 1; }; }
    todo released && { step released $TIER compare $D $OC released || return 1; }
    todo checkin && { step checkin $TIER checkin $D $OC || return 1; }
    todo check && { step check docker run --rm --network brickkit-$lc-net --user "$(id -u)" -v $BIN/be-ops:/be-ops:ro -v $OC:/work \
      -v $D/.secrets/tls/ops-recover.cert.pem:/certs/cert.pem:ro -v $D/.secrets/tls/ops-recover.key.pem:/certs/key.pem:ro \
      -v $D/.secrets/tls/ca.pem:/certs/ca.pem:ro -e SERVICE_TLS_CERT_FILE=/certs/cert.pem -e SERVICE_TLS_KEY_FILE=/certs/key.pem \
      -e SERVICE_TLS_CA_FILE=/certs/ca.pem -e DEPLOYMENT_ID=$DEP alpine:3.24.2 /be-ops recover verify-calls \
      --in /work/check-in.json --out /work/check-out.json || return 1; }
    todo check-result && { step check-result python3 -c "
import json, sys
rep = json.load(open('$OC/check-out.json'))
bad = 0
for m in json.load(open('$OC/check-in.json'))['members']:
    got = (rep.get('checks') or {}).get(m, [])
    for c in got:
        print(m, c['check'], c['outcome'], (c.get('detail') or '')[:160])
    bad += not got or any(c['outcome'] != 'pass' for c in got)
    if m.startswith('test/probe-py'):
        bad += not any(c['check'] == 'be.tiering' and c['outcome'] == 'pass' for c in got)
print('failed', rep.get('failed'), 'unimplemented', rep.get('unimplemented'))
sys.exit(1 if bad or rep.get('failed') or rep.get('unimplemented') else 0)" || return 1; }
    todo profile && { step profile bash -c "cd $CONF && uv run python -m cells profile $D" || return 1; }
    return 0
  }
  run; rc=$?; FROM=
  echo "$C rc=$rc" >> $O/summary.txt
  bash $R/dev/rebuild/experiment-scripts/cell-logs.sh $D $OC/containers D > /dev/null 2>&1
  [ -d $D/reports ] && cp -r $D/reports $OC/
  if [ $rc -eq 0 ] || [ "${DOWN:-}" = 1 ]; then (cd $D && brickkit down > /dev/null 2>&1)
  else  # left up for the fix and the resume; the next cell would meet the same problem
    failed=$(grep "^$C FAILED " $O/summary.txt | tail -1 | cut -d' ' -f3)
    echo "$C left up: resume with CELLS=$C FROM=$failed bash $O/run.sh, or stop with (cd $D && brickkit down)" >> $O/summary.txt
    break
  fi
done
echo "T11 ALL-DONE" >> $O/summary.txt
