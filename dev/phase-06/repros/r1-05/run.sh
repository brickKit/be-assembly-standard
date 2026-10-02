#!/usr/bin/env bash
# R1 #5：PG16 的 GRANT m TO shell WITH INHERIT FALSE, SET TRUE 之后，
# 外壳角色能 SET LOCAL ROLE m，但自己对成员的表没有任何权限（P19.5）。
# 用法：./run.sh            （默认 postgres:16-alpine）
#       PG_IMAGE=postgres:17-alpine ./run.sh
set -uo pipefail
cd "$(dirname "$0")"

IMAGE="${PG_IMAGE:-postgres:16-alpine}"
NAME="r1-r1a-pg05-$$"
pass=0; fail=0

cleanup() { docker rm -f -v "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=app "$IMAGE" >/dev/null
for _ in $(seq 1 60); do
  docker exec "$NAME" pg_isready -U postgres -d app -q 2>/dev/null && break
  sleep 0.5
done
sleep 1  # 镜像的 init 阶段会重启一次服务，等它真正就绪

psql_as() { # role sql...
  local role="$1"; shift
  docker exec -i "$NAME" psql -X -q -At -v ON_ERROR_STOP=1 -U "$role" -d app -c "$*" 2>&1
}

check() { # id expect(ok|err) pattern role sql
  local id="$1" expect="$2" pattern="$3" role="$4" sql="$5" out rc
  out="$(psql_as "$role" "$sql")"; rc=$?
  local got=ok; [ $rc -ne 0 ] && got=err
  if [ "$got" = "$expect" ] && grep -qE -- "$pattern" <<<"$out"; then
    echo "PASS $id"; pass=$((pass+1))
  else
    echo "FAIL $id (expect=$expect got=$got)"; fail=$((fail+1))
  fi
  sed 's/^/     | /' <<<"$out"
}

echo "== image: $IMAGE"
psql_as postgres "SELECT version();"
echo "== setup"
docker exec -i "$NAME" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d app <setup.sql

echo "== checks"
# C1 外壳角色直接读成员的表：没有 schema USAGE
check C1-shell-direct-read err "permission denied for schema s1" shell \
  "SELECT * FROM s1.orders;"

# C2 权限函数：外壳对 m1 是成员（MEMBER）、可 SET，但不继承（USAGE=f），对 schema/表无权限
#    （表用 OID 传：按名字 's1.orders' 解析本身就需要 schema USAGE，会直接报错）
check C2-shell-privileges ok "^f\|f\|f\|t\|t$" shell \
  "SELECT has_schema_privilege('s1','USAGE'),
          has_table_privilege((SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                               WHERE n.nspname='s1' AND c.relname='orders'), 'SELECT'),
          pg_has_role('m1','USAGE'), pg_has_role('m1','MEMBER'), pg_has_role('m1','SET');"

# C3 事务里 SET LOCAL ROLE + SET LOCAL search_path 之后可读写；P10.7 启动探测为真
check C3-set-local-role-rw ok "^m1\|shell\|s1$" shell \
  "BEGIN;
   SET LOCAL ROLE m1;
   SET LOCAL search_path TO s1;
   INSERT INTO orders VALUES (2, 'via shell');
   SELECT count(*) FROM orders;
   SELECT has_schema_privilege(current_user, current_schema(), 'USAGE,CREATE');
   SELECT current_user, session_user, current_schema();
   COMMIT;"

# C4 同一会话 COMMIT 之后，身份和 search_path 都回到外壳自己（池里的下一个借用者不受影响）
check C4-reverts-after-commit ok "^shell\|\"\\\$user\", public$" shell \
  "BEGIN; SET LOCAL ROLE m1; SET LOCAL search_path TO s1; COMMIT;
   SELECT current_user || '|' || current_setting('search_path');"
check C4b-no-access-after-commit err "permission denied for schema s1" shell \
  "BEGIN; SET LOCAL ROLE m1; SELECT 1 FROM s1.orders LIMIT 1; COMMIT;
   SELECT * FROM s1.orders;"

# C5 在 SET LOCAL ROLE m1 下建表，属主是 m1，不是 shell（P10.7 "属主都是 PG_USER" 能成立）
check C5-ddl-owner ok "^m1$" shell \
  "BEGIN; SET LOCAL ROLE m1; SET LOCAL search_path TO s1;
   CREATE TABLE made_in_shell (id int);
   COMMIT;
   SELECT tableowner FROM pg_tables WHERE schemaname='s1' AND tablename='made_in_shell';"

# C6 角色属性 INHERIT、授权 INHERIT FALSE：按授权算，仍然没有权限
check C6-grant-level-inherit-wins err "permission denied for schema s1" shell_inh \
  "SELECT * FROM s1.orders;"

# C7 对照组（先见红）：今天的默认继承授权，外壳角色能直接读成员的表
check C7-control-old-inherit ok "^1\|seed" shell_old \
  "SELECT * FROM s1.orders WHERE id=1;"

# C8 对照组：SET FALSE 时连 SET LOCAL ROLE 都不行
check C8-control-set-false err "permission denied to set role \"m1\"" shell_noset \
  "BEGIN; SET LOCAL ROLE m1; COMMIT;"

# C9 自身身份下 RESET ROLE 回到外壳：因为外壳不继承，回去也拿不到任何权限
check C9-reset-role-escape err "permission denied for schema s1" shell \
  "BEGIN; SET LOCAL ROLE m1; RESET ROLE; SELECT * FROM s1.orders; COMMIT;"

# C10 成员 m1 身份下读 m2 的表：m1 自己没有权限
check C10-member-cannot-read-peer err "permission denied for schema s2" shell \
  "BEGIN; SET LOCAL ROLE m1; SELECT * FROM s2.secrets; COMMIT;"

# C11 但 m1 的代码可以在同一事务里再 SET LOCAL ROLE m2：SET ROLE 检查的是会话用户（shell），
#     所以外壳里成员之间的隔离靠 SDK，不靠数据库
check C11-member-can-switch-to-peer ok "^m2\|m2-only$" shell \
  "BEGIN; SET LOCAL ROLE m1; SET LOCAL ROLE m2; SELECT current_user, note FROM s2.secrets; COMMIT;"

# C12 单跑：成员以自己登录，SET LOCAL ROLE 自己（P10.2 不分单跑和外壳）
check C12-standalone-self-set-role ok "^m1$" m1 \
  "BEGIN; SET LOCAL ROLE m1; SET LOCAL search_path TO s1; SELECT current_user; COMMIT;"

# C13 pg_stat_activity：SET LOCAL ROLE 期间 usename 仍是登录角色 shell
docker exec "$NAME" psql -X -q -At -U shell -d app \
  -c "BEGIN; SET LOCAL ROLE m1; SELECT pg_sleep(3); COMMIT;" >/dev/null 2>&1 &
bg=$!
sleep 1
check C13-pg-stat-activity-usename ok "^shell\|m1-busy$" postgres \
  "SELECT usename || '|' || CASE WHEN query LIKE '%pg_sleep%' THEN 'm1-busy' ELSE 'other' END
   FROM pg_stat_activity WHERE query LIKE '%pg_sleep(3)%' AND pid <> pg_backend_pid();"
wait $bg

# C14 修正方案的验证：事务里 SET LOCAL application_name = 成员 ID，pg_stat_activity 实时可见，提交后复原
docker exec "$NAME" psql -X -q -At -U shell -d app \
  -c "BEGIN; SET LOCAL ROLE m1; SET LOCAL application_name = 'member:m1'; SELECT pg_sleep(3); COMMIT;" >/dev/null 2>&1 &
bg=$!
sleep 1
check C14-set-local-application-name ok "^shell\|member:m1$" postgres \
  "SELECT usename || '|' || application_name
   FROM pg_stat_activity WHERE query LIKE '%pg_sleep(3)%' AND pid <> pg_backend_pid();"
wait $bg
check C14b-application-name-reverts ok "^psql$" shell \
  "BEGIN; SET LOCAL application_name = 'member:m1'; COMMIT; SHOW application_name;"

echo "== result: pass=$pass fail=$fail"
[ $fail -eq 0 ]
