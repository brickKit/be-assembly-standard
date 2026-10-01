#!/usr/bin/env bash
# 补齐本地 .env（已 gitignore）里数据库登录角色的随机密码：
#   <REPO>_DB_PASSWORD（schemas.tsv 每一行一个）与 SHELL_<NAME>_PASSWORD。
# 只追加缺失的条目，绝不覆盖已有值；只打印变量名，不打印值。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/infra/scripts/lib/db-pw.sh"
ENVF="$ROOT/.env"
touch "$ENVF"
added=()
while read -r _ var; do
  if ! grep -q "^${var}=" "$ENVF"; then
    [ -s "$ENVF" ] && [ -n "$(tail -c1 "$ENVF")" ] && echo >> "$ENVF"
    echo "${var}=$(openssl rand -hex 16)" >> "$ENVF"
    added+=("$var")
  fi
done < <(db_pw_pairs "$ROOT/registry/schemas.tsv")
if [ ${#added[@]} -eq 0 ]; then
  echo "✓ .env 里的数据库密码已齐全，无需补充"
else
  echo "✓ 已向 .env 追加 ${#added[@]} 项（只列名字）："
  printf '   %s\n' "${added[@]}"
fi
