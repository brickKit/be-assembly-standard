#!/bin/bash
# Step 13, E5: a second PostgreSQL instance, `second` in a cell's `databases:` (cells/spec.py). The base resources'
# image and settings (infra/docker-compose.infra.yml), the same admin password, on be-net as be-postgres-2 (the first
# instance reaches it there for the checks' postgres_fdw) and on host port 5433 (the components reach it through
# host.docker.internal). Its data lives in an anonymous volume and goes with `down`: it holds only the cells' data.
# Usage: postgres2.sh up|down
set -eu
R=/home/zhijie/Desktop/github/be-assembly-standard
IMAGE=$(sed -n 's/^ *image: \(postgres:.*\)$/\1/p' $R/infra/docker-compose.infra.yml | head -1)
case $1 in
  up)
    docker rm -fv be-postgres-2 >/dev/null 2>&1 || true
    docker run -d --name be-postgres-2 --network be-net -p 5433:5432 \
      -e POSTGRES_PASSWORD="$(grep '^POSTGRES_PASSWORD=' $R/.env | cut -d= -f2- | tr -d "\"'")" -e POSTGRES_DB=postgres \
      "$IMAGE" postgres -c max_connections=300 -c shared_preload_libraries=pg_stat_statements \
      -c idle_in_transaction_session_timeout=60s >/dev/null
    for _ in $(seq 60); do
      docker exec be-postgres-2 pg_isready -h localhost -p 5432 -U postgres >/dev/null 2>&1 && { echo "be-postgres-2 ready on 5433"; exit 0; }
      sleep 1
    done
    echo "be-postgres-2 not ready after 60 s" >&2; docker logs --tail 20 be-postgres-2 >&2; exit 1 ;;
  down) docker rm -fv be-postgres-2 >/dev/null 2>&1 || true; echo "be-postgres-2 removed" ;;
  *) echo "usage: $0 up|down" >&2; exit 2 ;;
esac
