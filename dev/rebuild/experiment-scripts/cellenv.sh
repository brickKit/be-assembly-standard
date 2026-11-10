# The environment every script that runs a business-chain cell needs, in one place (foundations item 6, retrospective
# P3: each run script copied part of cell-chain.sh's block, and two of them missed a variable the cell's config refers
# to). Source it: `. cellenv.sh [<cell directory>]`. Reads the secrets from the project's .env, never prints them.
#   always       envval, PW; the seed and test passwords; BE_ACC_PG_ADMIN, BE_ACC_NATS_URL, BE_ACC_S3_* (what the
#                cells' config files refer to and the suite's cell tools read); the identity member's Casdoor client
#                secrets (casdoor_secret); CASDOOR_ADMIN_PASSWORD
#   a cell       BE_ACC_CELL, SEED_OWNER_KEY (the deployment owner's key, cells/prepare.py writes it)
#   INCLUSTER=1  (set before sourcing) the base resources in the K row's cluster, on other host ports (step 10 B7)
#   build_be_ops <dir>  builds be-ops from source into <dir> (static: its calls also run in alpine), exports BE_OPS
#   recover_env <cell dir>  be-ops recover's environment for that cell: the run profile, its ops/recover certificate,
#                the bus and PostgreSQL's administrator
R=${R:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
PW=$(envval POSTGRES_PASSWORD)
PGP=${INCLUSTER:+15432}; PGP=${PGP:-5432}; NP=${INCLUSTER:+14222}; NP=${NP:-4222}; SP=${INCLUSTER:+19000}; SP=${SP:-9000}
export SEED_PASSWORD; SEED_PASSWORD=$(envval IAM_TEST_PASSWORD)
export IAM_TEST_PASSWORD="$SEED_PASSWORD" BE_ACC_IAM_TEST_PASSWORD="$SEED_PASSWORD"
export CASDOOR_ADMIN_PASSWORD; CASDOOR_ADMIN_PASSWORD=$(envval CASDOOR_ADMIN_PASSWORD)
export BE_ACC_PG_ADMIN="postgres://postgres:$PW@localhost:$PGP/postgres?sslmode=disable"
export BE_ACC_NATS_URL=nats://localhost:$NP BE_ACC_S3_URL=http://localhost:$SP
export BE_ACC_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY; BE_ACC_S3_ACCESS_KEY=$(envval STORAGE_ACCESS_KEY); BE_ACC_S3_SECRET_KEY=$(envval STORAGE_SECRET_KEY)
# the identity member's Casdoor applications: their client secrets live in Casdoor's own tables (local dev Casdoor)
casdoor_secret() {  # from whichever PostgreSQL holds Casdoor's schema: Docker's, or the cluster's (B7)
  local q="select client_secret from casdoor.application where client_id = '$1'"
  if [ -n "${INCLUSTER:-}" ]; then kubectl --context bek -n be-base exec deploy/be-postgres -- psql -U postgres -d brickkit_db -Atc "$q"
  else docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d brickkit_db -Atc "$q"; fi; }
export BE_ACC_IAM_CLIENT_SECRET BE_ACC_IAM_DEV_CLIENT_SECRET
BE_ACC_IAM_CLIENT_SECRET=$(casdoor_secret be-iam-client); BE_ACC_IAM_DEV_CLIENT_SECRET=$(casdoor_secret be-iam-dev-client)
if [ -n "${1:-}" ]; then
  export BE_ACC_CELL; BE_ACC_CELL=$(realpath "$1")
  export SEED_OWNER_KEY="$BE_ACC_CELL/.secrets/owner.key.pem"
fi
build_be_ops() {
  (cd "$R/tools/be-ops" && CGO_ENABLED=0 go build -o "$1/be-ops" ./cmd/be-ops) || return 1
  export BE_OPS="$1/be-ops"  # a secured cell's certificates come from its issuer (prepare.py)
}
recover_env() {
  export RUN_PROFILE_URL=http://localhost:$SP RUN_PROFILE_BUCKET=be-run-profile
  export RUN_PROFILE_ACCESS_KEY="$BE_ACC_S3_ACCESS_KEY" RUN_PROFILE_SECRET_KEY="$BE_ACC_S3_SECRET_KEY"
  export SERVICE_TLS_CERT_FILE="$1/.secrets/tls/ops-recover.cert.pem" SERVICE_TLS_KEY_FILE="$1/.secrets/tls/ops-recover.key.pem"
  export SERVICE_TLS_CA_FILE="$1/.secrets/tls/ca.pem" BUS_URL=nats://localhost:$NP
  export RECOVER_PG_ADMIN="$BE_ACC_PG_ADMIN"
}
