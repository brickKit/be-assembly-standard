#!/usr/bin/env bash
# 执行 be-ops 产出的建库脚本（幂等）。每个 pw_<role> 变量由 .env 里对应环境变量提供，
# 缺任何一个就报错并点名，建议跑 dev-env.sh。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/infra/scripts/lib/db-pw.sh"
[ -f .env ] || { echo "✗ 找不到 .env——先运行 bash infra/scripts/dev-env.sh" >&2; exit 1; }
set -a; . ./.env; set +a
# 口令以 \set 行写进 psql 的 stdin，不出现在 docker exec / psql 的命令行参数里
PW_FILE="$(mktemp)"; chmod 600 "$PW_FILE"; trap 'rm -f "$PW_FILE"' EXIT
db_pw_set_lines "$ROOT" > "$PW_FILE"
if [ ${#DB_PW_MISSING[@]} -gt 0 ]; then
  echo "✗ .env 缺少以下环境变量（${#DB_PW_MISSING[@]} 项）：" >&2
  printf '   %s\n' "${DB_PW_MISSING[@]}" >&2
  echo "  运行 bash infra/scripts/dev-env.sh 自动补齐（随机值，只追加不覆盖）" >&2
  exit 1
fi
(cd tools/be-ops && go build -o build/be-ops ./cmd/be-ops)
tools/be-ops/build/be-ops db-script --root . --out build/db-init.sql
{ cat "$PW_FILE"; cat build/db-init.sql; } | docker exec -i be-postgres psql -v ON_ERROR_STOP=1 -U postgres -f -
echo "✓ 建库脚本已执行（幂等，可重跑）"
