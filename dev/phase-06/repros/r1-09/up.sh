#!/usr/bin/env bash
# 起一套一次性的 Casdoor + PostgreSQL（与 be-casdoor / be-postgres 完全无关）。
# 镜像与 infra/docker-compose.infra.yml 相同：casbin/casdoor:latest，按本机摘要钉死。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CASDOOR_IMAGE="casbin/casdoor@sha256:1c4424819af678635d55e6979088761f526fe5a58f331ba94c371c4c0c81521f"
docker network create r1-k2-net >/dev/null 2>&1 || true
docker run -d --name r1-k2-pg --network r1-k2-net \
  -e POSTGRES_PASSWORD=r1k2-throwaway -e POSTGRES_DB=casdoor \
  postgres:16-alpine >/dev/null
until docker exec r1-k2-pg pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
docker run -d --name r1-k2-casdoor --network r1-k2-net \
  -p 127.0.0.1:38000:8000 -e RUNNING_IN_DOCKER=true \
  -v "$HERE/casdoor-conf:/conf:ro" \
  "$CASDOOR_IMAGE" >/dev/null
for i in $(seq 1 90); do
  curl -fsS http://localhost:38000/api/health >/dev/null 2>&1 && { echo "casdoor up after ${i}s"; exit 0; }
  sleep 1
done
echo "casdoor did not come up"; docker logs --tail 50 r1-k2-casdoor; exit 1
