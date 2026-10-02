#!/usr/bin/env bash
# r1-04b: pgx v5 against a throwaway PostgreSQL 16 container, reusing ../r1-04/setup.sql.
# Usage: PG_CONTAINER=r1-x3-pg ./run.sh     (container must already run, see README)
set -euo pipefail
cd "$(dirname "$0")"
C=${PG_CONTAINER:-r1-x3-pg}
PORT=$(docker port "$C" 5432/tcp | head -1 | sed 's/.*://')
export PG_DSN="postgres://shell:shell@127.0.0.1:${PORT}/r1db"

reset_data() {
  docker exec "$C" psql -q -U postgres -c 'DROP DATABASE IF EXISTS r1db' -c 'CREATE DATABASE r1db' 2>/dev/null
  docker exec -i "$C" psql -q -v ON_ERROR_STOP=1 -U postgres -d r1db < ../r1-04/setup.sql 2>/dev/null
}

BIN=$(mktemp -d)/r1-04b
(cd go && go build -o "$BIN" .)
for args in "cache_statement" "cache_describe" "describe_exec" "exec" "simple_protocol" \
            "cache_statement prefix" "cache_describe prefix"; do
  reset_data
  # shellcheck disable=SC2086
  "$BIN" $args
done
