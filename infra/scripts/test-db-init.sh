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
# 用法：infra/scripts/test-db-init.sh
set -euo pipefail

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
docker exec -i be-postgres psql -v ON_ERROR_STOP=1 -U postgres \
	-v pw_shell_go_core="$SHELL_GO_CORE_PASSWORD" \
	-v pw_shell_go_backoffice="$SHELL_GO_BACKOFFICE_PASSWORD" \
	-v pw_shell_go_infra="$SHELL_GO_INFRA_PASSWORD" \
	-v pw_shell_py_brain="$SHELL_PY_BRAIN_PASSWORD" \
	-v pw_shell_py_render="$SHELL_PY_RENDER_PASSWORD" \
	-f - < tools/be-ops/build/test-db-init.sql >/dev/null

# 已建组件里真的有数据库的那 12 个——infra-bff-mobile（§6.5 铁律二严禁
# 直连 DB）和 frontend-standard（无数据）没有 schema，天然跳过。
COMPONENTS=(
	mdm/customer mdm/product erp/inventory erp/finance erp/sales
	infra/authz infra/iam-casdoor infra/workflow infra/notification
	integration/im-dingtalk infra/print crm/opportunity
)

echo "▸ ② 对 ${#COMPONENTS[@]} 个已建组件各跑一遍 migrate-idempotent，目标 brickkit_test_db"
for c in "${COMPONENTS[@]}"; do
	echo "  - $c"
	( cd "components/$c" && \
	  DATABASE_HOST=localhost DATABASE_PORT=5432 DATABASE_USER=postgres \
	  DATABASE_PASSWORD="$POSTGRES_PASSWORD" DATABASE_NAME=brickkit_test_db \
	  make migrate-idempotent ) || { echo "✗ $c 迁移失败" >&2; exit 1; }
done

echo "✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db"
