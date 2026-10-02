#!/usr/bin/env bash
# 补齐本地 .env（已 gitignore）里数据库登录角色的随机密码：
#   <REPO>_DB_PASSWORD（schemas.tsv 每一行一个）与 SHELL_<NAME>_PASSWORD（每个外壳一个，同 be-ops）。
# 缺失或为空（VAR=）的条目才补，绝不覆盖已有非空值；只打印变量名，不打印值。
set -euo pipefail
# 整个脚本在项目锁里执行（写共享的库/.env；已持锁时直通）
[ -n "${BE_PROJECT_LOCK_HELD:-}" ] || exec bash "$(dirname "${BASH_SOURCE[0]}")/project-lock.sh" -- bash "${BASH_SOURCE[0]}" "$@"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/infra/scripts/lib/db-pw.sh"
ENVF="$ROOT/.env"
if [ ! -e "$ENVF" ]; then
  touch "$ENVF" 2>/dev/null || { echo "✗ 无法创建 $ENVF——检查仓库根目录的写权限" >&2; exit 1; }
fi
[ -w "$ENVF" ] || { echo "✗ $ENVF 不可写——检查文件权限" >&2; exit 1; }
added=()
while read -r _ var; do
  if grep -q "^${var}=." "$ENVF"; then continue; fi          # 已有非空值：不动
  val="$(openssl rand -hex 16)"
  if grep -q "^${var}=$" "$ENVF"; then                         # 空值 VAR=：原地填上
    sed -i "s|^${var}=\$|${var}=${val}|" "$ENVF"
  else
    [ -s "$ENVF" ] && [ -n "$(tail -c1 "$ENVF")" ] && echo >> "$ENVF"
    echo "${var}=${val}" >> "$ENVF"
  fi
  added+=("$var")
done < <(db_pw_pairs "$ROOT")
if [ ${#added[@]} -eq 0 ]; then
  echo "✓ .env 里的数据库密码已齐全，无需补充"
else
  echo "✓ 已向 .env 补齐 ${#added[@]} 项（只列名字）："
  printf '   %s\n' "${added[@]}"
fi
