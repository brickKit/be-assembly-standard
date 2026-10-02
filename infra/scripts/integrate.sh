#!/usr/bin/env bash
# 把一个组件（或外壳）接入项目：dev-env/db-init → brickkit add 或 upgrade → config-fill → teardown-sync → lint → up --dry-run。
# 持项目锁执行（改 brickkit.yaml、deploy*.yaml、config/、AGENTS.md、.env 与数据库角色）；任一步失败退出 1。
#
# 用法：bash infra/scripts/integrate.sh <id> [版本]     （make integrate ID=<id> [VERSION=<版本>]）
#   版本默认：外壳 be/* 是 1.0.0，其余 2.0.0
#   外壳同样适用：brickkit add be/<name>@1.0.0 会把已在项目里的成员移进外壳。
# 环境变量：BE_ROOT（项目根，默认本仓库；测试用）、BE_SKIP_DB_INIT=1（跳过 make dev-env db-init；测试用）
set -uo pipefail
# 先核对 brickkit 版本（不对就不等项目锁、直接退出 2）
source "$(dirname "${BASH_SOURCE[0]}")/lib/require-brickkit.sh"; require_brickkit
[ -n "${BE_PROJECT_LOCK_HELD:-}" ] || exec bash "$(dirname "${BASH_SOURCE[0]}")/project-lock.sh" -- bash "${BASH_SOURCE[0]}" "$@"

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BE_ROOT:-$(cd "$S/../.." && pwd)}"
ID="${1:-}"
[[ "$ID" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] || { echo "用法：integrate.sh <scope>/<name> [版本]（外壳：be/<name>）" >&2; exit 2; }
DEFAULT_VER=2.0.0; [ "${ID%%/*}" = be ] && DEFAULT_VER=1.0.0
VER="${2:-$DEFAULT_VER}"
REPO="${ID//\//-}"
cd "$ROOT" || exit 1

n=0
step() { n=$((n + 1)); echo; echo "▸ $n. $*"; }
die() { echo "✗ 第 $n 步失败：$*" >&2; exit 1; }
runv() { echo "  \$ $*"; "$@"; }

echo "▶ integrate $ID@$VER（项目 $ROOT）"

# 1. 连库组件（registry/schemas.tsv 有它的行）与外壳：先补 .env 密码、建角色与 schema
step "数据库角色与密码（make dev-env db-init）"
[ -r registry/schemas.tsv ] || die "读不到 registry/schemas.tsv（判断是否连库要用它；不当成\"不连库\"悄悄跳过）"
needs_db=0
if [ "${ID%%/*}" = be ] || awk -F'\t' -v r="$REPO" '!/^#/ && $1==r {f=1} END{exit !f}' registry/schemas.tsv; then needs_db=1; fi
if [ "$needs_db" = 0 ]; then
  echo "  不连库（registry/schemas.tsv 没有 $REPO），跳过"
elif [ -n "${BE_SKIP_DB_INIT:-}" ]; then
  echo "  BE_SKIP_DB_INIT 已设置，跳过"
else
  runv make --no-print-directory dev-env db-init || die "make dev-env db-init"
fi

# 2. 加入或升级
step "加入项目（brickkit add / upgrade）"
cur="$(python3 - "$ID" <<'PY'
import sys, yaml
d = yaml.safe_load(open("brickkit.yaml", encoding="utf-8")) or {}
print(next((str(c.get("version")) for c in d.get("components") or [] if c.get("id") == sys.argv[1] and not c.get("requiredBy")), ""))
PY
)" || die "读 brickkit.yaml 失败"
if [ -z "$cur" ]; then
  runv brickkit add "$ID@$VER" --yes || die "brickkit add $ID@$VER"
elif [ "$cur" = "$VER" ]; then
  echo "  brickkit.yaml 里已是 $ID@$VER，跳过 add / upgrade"
else
  echo "  brickkit.yaml 里是 $ID@$cur → 升级到 $VER；先看发布说明与改动："
  runv brickkit upgrade "$ID@$VER" --dry-run || die "brickkit upgrade $ID@$VER --dry-run"
  runv brickkit upgrade "$ID@$VER" --yes || die "brickkit upgrade $ID@$VER"
  echo "  ⚠️ --yes 会把配置冲突写成重复键；后面的 brickkit lint 报重复键时，按 brickkit-assemble skill 逐个解决再重跑"
fi

# 3. 填配置
step "填写 config/$REPO.yaml（config-fill.py）"
python3 "$S/config-fill.py" "$ID" --root "$ROOT"; rc=$?
if [ $rc -eq 3 ]; then
  echo "  给上面列出的键值后重跑（已加入的组件不会重复 add，已有值的键不会被覆盖）："
  echo "  bash infra/scripts/project-lock.sh -- python3 infra/scripts/config-fill.py $ID --set 'KEY=VALUE' …   # 值里有 \$ 时用单引号"
  die "config/$REPO.yaml 还有 required 键需要人给值"
fi
[ $rc -eq 0 ] || die "config-fill.py 退出 $rc"

# 4. 同步拆回验证的部署文件
step "同步 deploy.teardown.yaml（teardown-sync.py）"
python3 "$S/teardown-sync.py" --root "$ROOT" || die "teardown-sync.py"

# 5. 离线检查
step "brickkit lint --strict $ID"
runv brickkit lint --strict "$ID" || die "brickkit lint --strict $ID（重复键 / 未定义的 \$var: / .env 缺变量 / 文档警告）"

# 6. 生成检查
step "brickkit up --dry-run"
runv brickkit up --dry-run || die "brickkit up --dry-run"

step "项目文件的改动（控制者按路径提交）"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git status --short -- brickkit.yaml 'deploy*.yaml' config/ AGENTS.md registry/
else
  echo "  （不是 Git 仓库，跳过）"
fi
echo
echo "✓ integrate $ID@$VER 完成；下一步：make verify ID=$ID [ROUTE='<受保护路径>'] [FOCUS=1]"
