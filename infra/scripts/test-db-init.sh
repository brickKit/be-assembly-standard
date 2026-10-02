#!/usr/bin/env bash
# 建/刷新本地测试专用库 brickkit_test_db——跟真机演示/体验数据用的
# brickkit_db 物理分开，同一个 be-postgres 容器里的另一个 database，
# 不是另起一个容器（用户明确问过"要不要另起数据库"，这里选的是最轻的
# 那种：同实例内第二个 database，PostgreSQL 里角色是集群级对象不用
# 重建，只有 schema 是 per-database 的需要在这个库里单独建一份）。
#
# 幂等，可重跑：`be-ops db-script` 产出的建库/建 schema/授权语句本身
# 幂等（IF NOT EXISTS / DO 块判存在），每个组件的迁移走的是各自既有的
# migrate-idempotent 目标（golang-migrate/yoyo 的 up 本来就设计成可以
# 重复调用）。
#
# 用法：infra/scripts/test-db-init.sh [<scope>/<name>]
#   不带参数：建库 + 全部组件跑 migrate-idempotent；带组件 ID：建库 + 只跑这一个
#   （并行开发时别的组件半成品的迁移挡不住你）。
set -euo pipefail
# 整个脚本在项目锁里执行（写共享的库/.env；已持锁时直通）
[ -n "${BE_PROJECT_LOCK_HELD:-}" ] || exec bash "$(dirname "${BASH_SOURCE[0]}")/project-lock.sh" -- bash "${BASH_SOURCE[0]}" "$@"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
[ -f .env ] || { echo "✗ 找不到 .env（POSTGRES_PASSWORD 等从这里读）" >&2; exit 1; }
set -a; . ./.env; set +a

docker ps --filter "name=^be-postgres$" --filter "status=running" --format '{{.Names}}' | grep -q be-postgres || {
	echo "✗ be-postgres 没在跑——先 make up" >&2
	exit 1
}

echo "▸ ① 生成 + 应用建库脚本（brickkit_test_db + 54 个组件的 schema）"
( cd tools/be-ops && go build -o build/be-ops ./cmd/be-ops )
tools/be-ops/build/be-ops db-script --root . --out tools/be-ops/build/test-db-init.sql --database brickkit_test_db
# 口令走 stdin 的 \set 行，不进 argv（与 db-init.sh 同一套）
source "$ROOT/infra/scripts/lib/db-pw.sh"
PW_FILE="$(mktemp)"; chmod 600 "$PW_FILE"; trap 'rm -f "$PW_FILE"' EXIT
db_pw_set_lines "$ROOT" > "$PW_FILE"
if [ ${#DB_PW_MISSING[@]} -gt 0 ]; then
	echo "✗ .env 缺少：${DB_PW_MISSING[*]}——运行 bash infra/scripts/dev-env.sh" >&2
	exit 1
fi
{ cat "$PW_FILE"; cat tools/be-ops/build/test-db-init.sql; } | docker exec -i be-postgres psql -v ON_ERROR_STOP=1 -U postgres -f - >/dev/null

# 已建组件里真的有数据库的那 12 个——infra-bff-mobile（§6.5 铁律二严禁
# 直连 DB）和 frontend-standard（无数据）没有 schema，天然跳过。
COMPONENTS=(
	mdm/customer mdm/product erp/inventory erp/finance erp/sales
	infra/authz infra/iam-casdoor infra/workflow infra/notification
	integration/im-dingtalk infra/print crm/opportunity
)

if [ $# -gt 0 ]; then
	want="$1"; found=
	for c in "${COMPONENTS[@]}"; do [ "$c" = "$want" ] && found=1; done
	[ -n "$found" ] || { echo "✗ $want 不在有数据库的组件清单里：${COMPONENTS[*]}" >&2; exit 2; }
	COMPONENTS=("$want")
fi

echo "▸ ② 对 ${#COMPONENTS[@]} 个已建组件各跑一遍 migrate-idempotent，目标 brickkit_test_db"
for c in "${COMPONENTS[@]}"; do
	echo "  - $c"
	( cd "components/$c" && \
	  schema="$(awk -F'\t' -v r="$(basename "$(dirname "components/$c")")-$(basename "$c")" '$1==r {print $2}' "$ROOT/registry/schemas.tsv")"; \
	  pwvar="$(echo "$(basename "$(dirname "components/$c")")-$(basename "$c")" | tr 'a-z-' 'A-Z_')_DB_PASSWORD"; \
	  PG_HOST=localhost PG_PORT=5432 PG_DATABASE=brickkit_test_db \
	  PG_USER="${schema}_rw" PG_PASSWORD="${!pwvar:-}" PG_SCHEMA="$schema" \
	  DATABASE_HOST=localhost DATABASE_PORT=5432 DATABASE_USER=postgres \
	  DATABASE_PASSWORD="$POSTGRES_PASSWORD" DATABASE_NAME=brickkit_test_db \
	  make migrate-idempotent ) || { echo "✗ $c 迁移失败" >&2; exit 1; }
done

echo "✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db"
