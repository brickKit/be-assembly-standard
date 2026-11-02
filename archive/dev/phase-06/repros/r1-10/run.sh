#!/usr/bin/env bash
# r1-10: run check.py in throwaway python containers (nothing installed on the host).
# Needs a throwaway PG16 for the asyncpg smoke step: PG_CONTAINER (default r1-r1b-pg).
set -uo pipefail
cd "$(dirname "$0")"
C=${PG_CONTAINER:-r1-r1b-pg}
PORT=$(docker port "$C" 5432/tcp | head -1 | sed 's/.*://')
export PG_DSN="postgres://postgres:pw@127.0.0.1:${PORT}/postgres"
for img in python:3.14-slim python:3.13-slim python:3.14-alpine; do
  for mode in pinned latest; do
    docker run --rm --network host -e PG_DSN -v "$PWD:/w:ro" "$img" python /w/check.py native "$mode"
  done
done
docker run --rm -v "$PWD:/w:ro" python:3.14-slim python /w/check.py matrix
