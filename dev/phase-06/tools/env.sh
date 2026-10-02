#!/usr/bin/env bash
# 打印一个组件在 06b 闭环里用到的全部变量（component-loop §0.1），并建好它的 scratch 目录。
#
# 用法：eval "$(bash dev/phase-06/tools/env.sh <scope>/<name>)"
#   BE_SCRATCH   必填：当前会话的 scratchpad 目录（系统提示里给出的 …/scratchpad）；S=$BE_SCRATCH/06b/$REPO
#   BE_COMP_DIR  可选：组件目录，默认 $ROOT/components/<id>（测试用它指向 scratch 里的克隆）
#   BE_DOTENV    可选：.env 的路径，默认 $ROOT/.env（测试用）
# 输出的每一行都能被 bash / zsh eval：十个 `export NAME=值`；PATH 追加 $HOME/go/bin（追加在末尾，
# 绝不放前面——~/go/bin 里有旧的 brickkit v0.4.6，放前面会遮住 ~/.local/bin 的 v1.1.0）；
# TEST_PG_DSN / TEST_NATS_URL 在 eval 的那一刻才从 .env 读口令拼出来，输出里只有变量名、没有值
# （输出会出现在会话记录里）。
# 先核对工具：PATH（追加 go/bin 之后）上的 `brickkit version` 第一行必须是 BrickKit CLI v1.1.0，buf 必须在。
# 出错时只往 stderr 写、退出码非零，所以 eval "$(…)" 不会吃进半截输出。
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

# ── 工具版本（component-loop 1.4）：按 eval 之后的 PATH 查 ──
WANT_BK='BrickKit CLI v1.1.0'
EPATH=$PATH:$HOME/go/bin
bk=$(PATH=$EPATH command -v brickkit || true)
[ -n "$bk" ] || die "PATH 上没有 brickkit（要 $WANT_BK，装在 ~/.local/bin）"
bkv=$(PATH=$EPATH brickkit version 2>/dev/null | head -1 || true)
[ "$bkv" = "$WANT_BK" ] || die "PATH 上的 brickkit 是 $bk：${bkv:-（brickkit version 没有输出）}，要 $WANT_BK（~/go/bin 放在 PATH 前面会遮住新版：改成 export PATH=\$PATH:\$HOME/go/bin）"
PATH=$EPATH command -v buf >/dev/null || die "PATH（含 \$HOME/go/bin）上没有 buf：上报控制者，不要自己另装"

# ── 测试连接（component-loop 4.17）：只核对 .env 里有口令这个键，不读出、不打印值 ──
DOTENV=${BE_DOTENV:-$ROOT/.env}
[ -f "$DOTENV" ] || die "没有 $DOTENV（TEST_PG_DSN 的口令从它的 POSTGRES_PASSWORD 读；先 make dev-env）"
grep -q '^POSTGRES_PASSWORD=' "$DOTENV" || die "$DOTENV 里没有 POSTGRES_PASSWORD 这个键（TEST_PG_DSN 要用）"
pw_ok=$( set +eu; . "$DOTENV" >/dev/null 2>&1; [[ ${POSTGRES_PASSWORD:-} =~ ^[A-Za-z0-9._~-]+$ ]] && echo y || true)
[ "$pw_ok" = y ] || die "$DOTENV 的 POSTGRES_PASSWORD 为空，或含 URL 里要转义的字符（拼进 TEST_PG_DSN 会坏；本脚本不做转义）"

mkdir -p "$S"
for v in ROOT ID REPO UREPO C S SCHEMA ROLE SVC NET; do
  printf 'export %s=%q\n' "$v" "${!v}"
done
# 下面三行原样输出（单引号），在 eval 的那一刻才展开：值不进会话记录
printf '%s\n' 'case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$PATH:$HOME/go/bin" ;; esac'
printf 'export TEST_PG_DSN="postgres://postgres:$( . %q >/dev/null 2>&1; printf %%s "$POSTGRES_PASSWORD" )@localhost:5432/brickkit_test_db?sslmode=disable"\n' "$DOTENV"
printf '%s\n' 'export TEST_NATS_URL=nats://localhost:4222'
echo "ℹ️  env.sh：$bkv（$bk）；buf 在；TEST_PG_DSN 由 $(basename "$DOTENV") 的 POSTGRES_PASSWORD 在 eval 时拼出（不打印值），TEST_NATS_URL=nats://localhost:4222" >&2
