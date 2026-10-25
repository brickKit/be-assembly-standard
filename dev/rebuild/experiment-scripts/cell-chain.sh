#!/bin/bash
# Step 8: brings one business-chain cell up from nothing and checks it: create, prepare, build, up, secure, seed data
# (twice: the second run must change nothing), the L3 scenarios. Stages write BEGIN/END lines to <out>/status.log, each
# stage's output to its own log; the first failing stage stops the run. The cell stays up unless KEEP_UP=0.
# Usage: cell-chain.sh <cell name, e.g. D8-S> <output directory>
set -u
CELL=$1; OUT=$(realpath -m "$2"); R=/home/zhijie/Desktop/github/be-assembly-standard
D=$R/dev/rebuild/experiment-cells/$CELL; CONF=$R/tools/be-acceptance/conformance
mkdir -p "$OUT/logs"; echo $$ > "$OUT/runner.pid"
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export SEED_PASSWORD; SEED_PASSWORD=$(envval IAM_TEST_PASSWORD)
export IAM_TEST_PASSWORD="$SEED_PASSWORD" BE_ACC_IAM_TEST_PASSWORD="$SEED_PASSWORD" BE_ACC_CELL="$D"
export CASDOOR_ADMIN_PASSWORD; CASDOOR_ADMIN_PASSWORD=$(envval CASDOOR_ADMIN_PASSWORD)
export BE_ACC_PG_ADMIN; BE_ACC_PG_ADMIN="postgres://postgres:$(envval POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
export BE_ACC_NATS_URL=nats://localhost:4222 BE_ACC_S3_URL=http://localhost:9000
export BE_ACC_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY; BE_ACC_S3_ACCESS_KEY=$(envval STORAGE_ACCESS_KEY); BE_ACC_S3_SECRET_KEY=$(envval STORAGE_SECRET_KEY)
# the identity member's Casdoor applications: their client secrets live in Casdoor's own tables (local dev Casdoor)
casdoor_secret() { docker exec -e PGPASSWORD="$(envval POSTGRES_PASSWORD)" be-postgres psql -U postgres -d brickkit_db -Atc \
  "select client_secret from casdoor.application where client_id = '$1'"; }
export BE_ACC_IAM_CLIENT_SECRET BE_ACC_IAM_DEV_CLIENT_SECRET
BE_ACC_IAM_CLIENT_SECRET=$(casdoor_secret be-iam-client); BE_ACC_IAM_DEV_CLIENT_SECRET=$(casdoor_secret be-iam-dev-client)
I=0
stage() {  # stage <name> <command...>; stops the run on failure
  I=$((I+1)); local name=$1; shift; local t0; t0=$(date +%s)
  echo "STAGE $I $name BEGIN $(date -Is)" >> "$OUT/status.log"
  ( "$@" ) > "$OUT/logs/$I-$name.log" 2>&1; local rc=$?
  echo "STAGE $I $name END exit=$rc secs=$(( $(date +%s) - t0 ))" >> "$OUT/status.log"
  if [ $rc -ne 0 ]; then echo "FAILED $name $(date -Is)" >> "$OUT/status.log"; exit $rc; fi
}
down_cells() {
  for p in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | grep '^brickkit-d' | sort -u); do
    docker compose -p "$p" down --remove-orphans; done
}
echo "START $CELL power=$(powerprofilesctl get) $(date -Is)" >> "$OUT/status.log"
stage down-others down_cells
stage create bash -c "cd $CONF && uv run python -m cells create $D && uv run python -m cells prepare $D"
stage build bash -c "cd $D && brickkit build"
stage up bash -c "cd $D && brickkit up"
stage secure bash -c "cd $CONF && uv run python -m cells secure $D"
stage seed-1 make -C "$R" seed-data
stage seed-2 make -C "$R" seed-data
stage scenarios bash -c "cd $CONF && uv run pytest -q scenarios"
[ "${KEEP_UP:-1}" = 0 ] && stage down bash -c "cd $D && brickkit down"
echo "ALL-DONE $(date -Is)" >> "$OUT/status.log"
