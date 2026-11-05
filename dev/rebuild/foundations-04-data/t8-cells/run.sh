#!/bin/bash
# Foundations item 4, T8's real run (the cascade: every member on be-sdk-go alpha.81, be/go-infra 3.0.52, suite 1.0.47):
# F3-S (every member alone), then F3-X (be/go-infra), each from an empty database through cell-chain.sh (create,
# (be/go-infra 3.0.51), each from an empty database through cell-chain.sh (create, prepare, build, up, install claim,
# seeds twice, L3), then down; after each cell, how many evidence records the store holds by recorder and phase.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/run.pid; : > $O/summary.txt
pgpw=$(grep '^POSTGRES_PASSWORD=' "$R/.env" | cut -d= -f2- | tr -d "\"'")
for c in ${CELLS:-F3-S F3-X}; do
  KEEP_UP=1 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh $c $O/$c > $O/$c.log 2>&1
  rc=$?; echo "$c rc=$rc" >> $O/summary.txt
  lc=$(echo $c | tr 'A-Z' 'a-z')
  # the evidence the store holds (infra/audit's schema in the cells' database be_experiment), by recorder and phase
  docker exec -e PGPASSWORD="$pgpw" be-postgres psql -U postgres -d be_experiment -Atc \
    "SELECT recorder, phase, count(*) FROM infra_audit.audit_evidence GROUP BY 1, 2 ORDER BY 1, 2" \
    > $O/$c/evidence.txt 2>&1
  if [ $rc -ne 0 ]; then
    for n in $(docker ps --format '{{.Names}}' | grep "brickkit-$lc-"); do docker logs $n > $O/$c/$n.container.log 2>&1; done
  fi
  (cd $R/dev/rebuild/experiment-cells/$c && brickkit down > /dev/null 2>&1)
done
echo "T8CELLS ALL-DONE" >> $O/summary.txt
