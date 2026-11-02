#!/usr/bin/env bash
# r1-04: run both drivers against a throwaway PostgreSQL 16 container.
# Usage: PG_CONTAINER=r1-r1b-pg ./run.sh     (container must already run, see README)
set -euo pipefail
cd "$(dirname "$0")"
C=${PG_CONTAINER:-r1-r1b-pg}
PORT=$(docker port "$C" 5432/tcp | head -1 | sed 's/.*://')
export PG_DSN="postgres://shell:shell@127.0.0.1:${PORT}/r1db"

reset_data() {
  docker exec "$C" psql -q -U postgres -c 'DROP DATABASE IF EXISTS r1db' -c 'CREATE DATABASE r1db' 2>/dev/null
  docker exec -i "$C" psql -q -v ON_ERROR_STOP=1 -U postgres -d r1db < setup.sql 2>/dev/null
}

# asyncpg in a throwaway python:3.13-slim container (host network to reach the mapped port)
for args in "100" "0" "100 prefix"; do
  reset_data
  docker run --rm --network host -e PG_DSN -v "$PWD/py:/w:ro" python:3.13-slim \
    sh -c "pip install -q --root-user-action=ignore asyncpg==0.30.0 2>/dev/null && python /w/repro.py $args"
done

# node-postgres with the local Node 24
(cd node && npm ci --silent)
for mode in unnamed named named-member; do
  reset_data
  node node/repro.mjs "$mode"
done
