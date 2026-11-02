#!/usr/bin/env bash
# R1 #6：golang-migrate（iofs）、yoyo、node-pg-migrate 是否忽略 migrations/lifecycle.yaml，
# 状态表能否放进组件自己的 schema，同一 schema 能否放两套状态表。
# 依赖：docker、go、uv（Python 3.14）、node ≥ 20。
set -uo pipefail
cd "$(dirname "$0")"
IMAGE="${PG_IMAGE:-postgres:16-alpine}"
NAME="r1-r1a-pg06-$$"
cleanup() { docker rm -f -v "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" -p 127.0.0.1::5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=app "$IMAGE" >/dev/null
for _ in $(seq 1 60); do docker exec "$NAME" pg_isready -U postgres -d app -q 2>/dev/null && break; sleep 0.5; done
sleep 1
PORT="$(docker port "$NAME" 5432/tcp | head -1 | sed 's/.*://')"

# 每个工具一个组件身份：角色名和 schema 名故意不同（不靠 "$user" 碰巧命中），public 上没有 CREATE（PG15+ 默认）
docker exec -i "$NAME" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d app <<'SQL'
CREATE ROLE c_go LOGIN PASSWORD 'pw';    CREATE SCHEMA s_go AUTHORIZATION c_go;
CREATE ROLE c_py LOGIN PASSWORD 'pw';    CREATE SCHEMA s_py AUTHORIZATION c_py;
CREATE ROLE c_node LOGIN PASSWORD 'pw';  CREATE SCHEMA s_node AUTHORIZATION c_node;
CREATE ROLE c_node2 LOGIN PASSWORD 'pw'; CREATE SCHEMA s_node2 AUTHORIZATION c_node2;
SQL
dsn() { echo "postgresql://$1:pw@127.0.0.1:$PORT/app"; }
rc=0

echo "== $(docker exec "$NAME" psql -At -U postgres -d app -c 'SHOW server_version')"
echo "== golang-migrate (iofs, pgx5)"
(cd go && DSN="$(dsn c_go)" PG_SCHEMA=s_go go run .) || rc=1

echo "== yoyo"
DSN="$(dsn c_py)" PG_SCHEMA=s_py uv run -q --no-project --python 3.14 \
  --with-requirements py/requirements.txt python py/run_yoyo.py || rc=1

echo "== node-pg-migrate"
(cd node && npm install --silent --no-audit --no-fund && \
  DSN="$(dsn c_node)" PG_SCHEMA=s_node DSN2="$(dsn c_node2)" PG_SCHEMA2=s_node2 node run.mjs) || rc=1

echo "== tables in public (must be none)"
docker exec "$NAME" psql -At -U postgres -d app -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'"
exit $rc
