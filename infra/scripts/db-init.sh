#!/usr/bin/env bash
# 执行 be-ops 产出的建库脚本（幂等）。每个 pw_<role> 变量由 .env 里对应环境变量提供，
# 缺任何一个就报错并点名，建议跑 dev-env.sh。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/infra/scripts/lib/db-pw.sh"
set -a; . ./.env; set +a
args=(); missing=()
while read -r pv ev; do
  if [ -z "${!ev:-}" ]; then missing+=("$ev"); continue; fi
  args+=(-v "$pv=${!ev}")
done < <(db_pw_pairs registry/schemas.tsv)
if [ ${#missing[@]} -gt 0 ]; then
  echo "✗ .env 缺少以下环境变量（${#missing[@]} 项）：" >&2
  printf '   %s\n' "${missing[@]}" >&2
  echo "  运行 bash infra/scripts/dev-env.sh 自动补齐（随机值，只追加不覆盖）" >&2
  exit 1
fi
(cd tools/be-ops && go build -o build/be-ops ./cmd/be-ops)
tools/be-ops/build/be-ops db-script --root . --out build/db-init.sql
docker exec -i be-postgres psql -v ON_ERROR_STOP=1 -U postgres "${args[@]}" -f - < build/db-init.sql
echo "✓ 建库脚本已执行（幂等，可重跑）"
