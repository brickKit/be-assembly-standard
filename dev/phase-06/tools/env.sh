#!/usr/bin/env bash
# 打印一个组件在 06b 闭环里用到的全部变量（component-loop §0.1），并建好它的 scratch 目录。
#
# 用法：eval "$(bash dev/phase-06/tools/env.sh <scope>/<name>)"
#   BE_SCRATCH   必填：当前会话的 scratchpad 目录（系统提示里给出的 …/scratchpad）；S=$BE_SCRATCH/06b/$REPO
#   BE_COMP_DIR  可选：组件目录，默认 $ROOT/components/<id>（测试用它指向 scratch 里的克隆）
# 输出的每一行都是 `export NAME=值`，bash / zsh 都能 eval。出错时只往 stderr 写、退出码非零，
# 所以 eval "$(…)" 不会吃进半截输出。
set -euo pipefail

die() { echo "❌ env.sh: $*" >&2; exit 2; }

ID=${1:-}
[ -n "$ID" ] || die "用法：eval \"\$(bash env.sh <scope>/<name>)\""
[[ $ID =~ ^[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "组件 ID 必须是 <scope>/<name>（小写），收到：$ID"
[ -n "${BE_SCRATCH:-}" ] || die "请先设置 BE_SCRATCH=<当前会话的 scratchpad 目录>（临时文件不进仓库）"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
REPO=${ID/\//-}
UREPO=$(printf '%s' "$REPO" | tr 'a-z-' 'A-Z_')
C=${BE_COMP_DIR:-$ROOT/components/$ID}
[ -f "$C/component.yaml" ] || die "组件目录 $C 里没有 component.yaml（ID 写错了，或 BE_COMP_DIR 指错了）"
C=$(cd "$C" && pwd)
S=$BE_SCRATCH/06b/$REPO
# schemas.tsv：repo  schema  role  shell_login_role；不连库的组件（bff-mobile、前端）没有这一行，两个值为空
SCHEMA=$(awk -F'\t' -v r="$REPO" '$1==r{print $2}' "$ROOT/registry/schemas.tsv")
ROLE=$(awk -F'\t' -v r="$REPO" '$1==r{print $3}' "$ROOT/registry/schemas.tsv")
SVC=$REPO-2-0-0
NET=brickkit-be-assembly-standard-net

mkdir -p "$S"
for v in ROOT ID REPO UREPO C S SCHEMA ROLE SVC NET; do
  printf 'export %s=%q\n' "$v" "${!v}"
done
