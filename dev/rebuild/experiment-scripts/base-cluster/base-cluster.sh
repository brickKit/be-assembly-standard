#!/bin/bash
# Step 10, B7: the base resources inside the K row's cluster (base.yaml, casdoor.yaml), in place of Docker's.
#   dump <file>  Casdoor's schema (applications, client secrets, test accounts, certificate) from Docker's be-postgres;
#                run while Docker's base resources are up
#   up <file>    load the four images into the node, create namespace be-base with its secret (from .env, values never
#                printed) and config map (infra/), start PostgreSQL, NATS and RustFS, restore the dump, start Casdoor,
#                wait until all four are ready and reachable on the host ports 15432, 14222, 19000, 18000
#   down         delete namespace be-base
#   docker-stop, docker-start   Docker's base resources (be-postgres, be-nats, be-rustfs, be-casdoor) off and on again:
#                the sampler finds base resources by these names, and two sets would be counted twice
# The node must be running (cluster-on.sh). Usage: base-cluster.sh <command> [file]
set -eu
R=/home/zhijie/Desktop/github/be-assembly-standard; H=$R/dev/rebuild/experiment-scripts/base-cluster
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl
K=(kubectl --context bek)
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
DOCKER_BASE="be-postgres be-nats be-rustfs be-casdoor"
IMAGES="postgres:16.15-alpine nats:2.10.29-alpine rustfs/rustfs:1.0.0-beta.12 casbin/casdoor:4.1.0"
case ${1:?usage: base-cluster.sh dump|up|down|docker-stop|docker-start [file]} in
dump)
  docker exec -e PGPASSWORD="$(envval POSTGRES_PASSWORD)" be-postgres pg_dump -U postgres -d brickkit_db -n casdoor \
    --no-owner > "${2:?dump file}"
  echo "casdoor schema: $(grep -c '^CREATE TABLE' "$2") tables, $(wc -c < "$2") bytes" ;;
up)
  F=${2:?dump file}; [ -s "$F" ] || { echo "no dump at $F"; exit 1; }
  for i in $IMAGES; do minikube -p bek image load "$i"; done
  "${K[@]}" create namespace be-base --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
  pw=$(envval POSTGRES_PASSWORD)
  "${K[@]}" -n be-base create secret generic be-base-env --dry-run=client -o yaml \
    --from-literal=POSTGRES_PASSWORD="$pw" \
    --from-literal=STORAGE_ACCESS_KEY="$(envval STORAGE_ACCESS_KEY)" \
    --from-literal=STORAGE_SECRET_KEY="$(envval STORAGE_SECRET_KEY)" \
    --from-literal=CASDOOR_DSN="user=postgres password=$pw host=base port=5432 sslmode=disable dbname=brickkit_db search_path=casdoor" \
    | "${K[@]}" apply -f - >/dev/null
  # only the database: the dump creates the casdoor schema itself
  printf 'CREATE DATABASE brickkit_db;\n' > /tmp/be-base-00-init.sql
  "${K[@]}" -n be-base create configmap be-base-conf --dry-run=client -o yaml \
    --from-file=00-init.sql=/tmp/be-base-00-init.sql --from-file=nats.conf="$R/infra/nats/nats.conf" \
    --from-file=app.conf="$R/infra/casdoor/conf/app.conf" | "${K[@]}" apply -f - >/dev/null
  rm -f /tmp/be-base-00-init.sql
  "${K[@]}" apply -f "$H/base.yaml"
  for d in be-postgres be-nats be-rustfs; do "${K[@]}" -n be-base rollout status deployment/$d --timeout=180s; done
  "${K[@]}" -n be-base exec -i deploy/be-postgres -- psql -q -v ON_ERROR_STOP=1 -U postgres -d brickkit_db < "$F"
  "${K[@]}" apply -f "$H/casdoor.yaml"
  "${K[@]}" -n be-base rollout status deployment/be-casdoor --timeout=300s
  for p in 15432 14222 19000 18000; do
    for i in $(seq 30); do bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null && break; sleep 2; done
    bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null || { echo "host port $p not reachable"; exit 1; }
  done
  echo "be-base up: $("${K[@]}" -n be-base get pods --no-headers | awk '{print $1, $2}' | tr '\n' ' ')" ;;
down)
  "${K[@]}" delete namespace be-base --wait=true --ignore-not-found ;;
docker-stop) docker stop $DOCKER_BASE ;;
docker-start)
  docker start $DOCKER_BASE
  for c in $DOCKER_BASE; do
    for i in $(seq 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$c")" = healthy ] && break; sleep 2; done
  done
  docker ps --format '{{.Names}} {{.Status}}' | grep -E "^($(echo $DOCKER_BASE | tr ' ' '|')) " ;;
*) echo "unknown command $1"; exit 1 ;;
esac
