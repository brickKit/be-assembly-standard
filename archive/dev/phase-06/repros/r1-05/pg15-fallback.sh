#!/usr/bin/env bash
# 附加：PG15 不认 GRANT … WITH INHERIT/SET 语法；看"角色级 NOINHERIT + 普通 GRANT"是否给出同样效果。
set -uo pipefail
IMAGE="${PG_IMAGE:-postgres:15}"
N="r1-r1a-pg15-$$"
trap 'docker rm -f -v "$N" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$N" -e POSTGRES_PASSWORD=postgres "$IMAGE" >/dev/null
for _ in $(seq 1 60); do docker exec "$N" pg_isready -U postgres -q 2>/dev/null && break; sleep 0.5; done
sleep 2
q() { docker exec -i "$N" psql -X -q -At -U "$1" -d postgres -c "$2" 2>&1 | sed "s/^/[$1] /"; }
q postgres "SELECT version();"
q postgres "CREATE ROLE m1 LOGIN; CREATE SCHEMA s1 AUTHORIZATION m1; SET ROLE m1; CREATE TABLE s1.t(id int); RESET ROLE;
            CREATE ROLE shell LOGIN NOINHERIT;"
q postgres "GRANT m1 TO shell WITH INHERIT FALSE, SET TRUE;"   # 期望：语法错误
q postgres "GRANT m1 TO shell;"
q shell    "SELECT * FROM s1.t;"                                 # 期望：permission denied
q shell    "BEGIN; SET LOCAL ROLE m1; SELECT current_user, count(*) FROM s1.t; COMMIT;"  # 期望：m1|0
