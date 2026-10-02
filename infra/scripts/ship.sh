#!/usr/bin/env bash
# 发布一个组件或外壳：推送 main → 契约包 tag（Go）→ brickkit release → v tag（Go）→ 外壳视角拉取检查（Go）→ 打印父仓库要提交的路径。
# 只有控制者运行。按顺序执行，第一处失败即停；已经推送的东西绝不回滚、删除或移动，只报告停在哪一步。
# 可以重跑：已在 HEAD 上的 tag 视为已完成；已推送却不在 HEAD 上的 tag 一律 FAIL（发新版本，不移动 tag）。
#
# 用法：bash infra/scripts/ship.sh [--dry-run] <组件目录：components/<scope>/<name> | shell/be/<name>> <发布说明文件>
#   --dry-run  只读检查照做（干净、分支、远端 tag、契约包 N-3 校验；为比较可能从远端取回提交对象，但不建任何本地引用），
#              改动类命令（push、tag、release、拉取探针）只打印
# 环境变量：SHIP_PROBE_RETRIES（拉取探针次数，默认 3）、SHIP_PROBE_INTERVAL（间隔秒数，默认 30）
set -uo pipefail
# brickkit release 交给旧 CLI 不会报错：dry-run 也先核对版本，不对就退出 2，一步都不走
source "$(dirname "${BASH_SOURCE[0]}")/lib/require-brickkit.sh"; require_brickkit

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
[ $# -eq 2 ] || { echo "用法：ship.sh [--dry-run] <components/<scope>/<name> | shell/be/<name>> <发布说明文件>" >&2; exit 2; }
ROOT="${BE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
case "$1" in /*) D="$1" ;; *) D="$ROOT/$1" ;; esac
D="$(cd "$D" 2>/dev/null && pwd -P)" || { echo "✗ 目录不存在：$1" >&2; exit 2; }
NOTES="$(realpath -m "$2")"
[ -f "$NOTES" ] || { echo "✗ 发布说明文件不存在：$2" >&2; exit 2; }
case "$NOTES" in "$D"/*) echo "✗ 发布说明必须放在组件目录之外（目录里的文件过不了 brickkit release 的干净检查）：$NOTES" >&2; exit 2 ;; esac
[ -f "$D/component.yaml" ] || { echo "✗ $D 下没有 component.yaml" >&2; exit 2; }
PROBE_RETRIES="${SHIP_PROBE_RETRIES:-3}"
PROBE_INTERVAL="${SHIP_PROBE_INTERVAL:-30}"

meta="$(python3 - "$D/component.yaml" <<'PY'
import sys, yaml
m = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
md = m.get("metadata") or {}
print(md.get("id", ""), md.get("version", ""), "1" if "shell" in m else "0")
PY
)" || { echo "✗ 读不了 $D/component.yaml" >&2; exit 2; }
read -r ID VER IS_SHELL <<< "$meta"
[[ "$ID" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] || { echo "✗ component.yaml 的 metadata.id 不是 <scope>/<name>：'${ID}'" >&2; exit 2; }
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ component.yaml 的 metadata.version 不是精确版本 x.y.z：'${VER}'" >&2; exit 2; }
REPO="${ID//\//-}"
IS_GO=0
[ -f "$D/go.mod" ] && [ "$IS_SHELL" = 0 ] && IS_GO=1
KIND="Python/TS 组件"; [ "$IS_GO" = 1 ] && KIND="Go 组件"; [ "$IS_SHELL" = 1 ] && KIND="外壳"
g() { git -C "$D" "$@"; }

N=0; TITLE=""
step() { N="$1"; TITLE="$2"; echo; echo "── 第 $N 步：$TITLE"; }
pass() { echo "▸ 第 $N 步 $TITLE … PASS${1:+（$1）}"; }
skip() { echo "▸ 第 $N 步 $TITLE … SKIP（$1）"; }
fail() {
  echo "▸ 第 $N 步 $TITLE … FAIL（$1）"
  echo "✗ 停在第 $N 步。之前已推送的东西保持原样（不回滚、不删除、不移动 tag）；修好原因后重跑本命令，已完成的步骤会被识别为 PASS。"
  exit 1
}
# 改动类命令：dry-run 只打印（g 显示成 git，命令都在组件目录里执行）
run() {
  local shown="$*"; [ "$1" = g ] && shown="git ${*:2}"
  if [ "$DRY" = 1 ]; then echo "  [dry-run] $shown"; return 0; fi
  echo "  \$ $shown"; "$@"
}
# 远端 tag 指向的提交（注解 tag 取 ^{} 解引用后的提交）；没有这个 tag 时输出空
remote_tag_commit() {
  local out peeled
  out="$(g ls-remote origin "refs/tags/$1" "refs/tags/$1^{}")" || return 1
  peeled="$(echo "$out" | awk -v r="refs/tags/$1^{}" '$2==r {print $1}')"
  if [ -n "$peeled" ]; then echo "$peeled"; else echo "$out" | awk -v r="refs/tags/$1" '$2==r {print $1}'; fi
}
local_tag_commit() { g rev-parse -q --verify "refs/tags/$1^{commit}" 2>/dev/null || true; }
# 确保本地有这个提交对象（比较用）；只取对象、不建 tag 引用，dry-run 下也安全
have_commit() { g cat-file -e "$1^{commit}" 2>/dev/null || g fetch -q --no-tags origin "$1" 2>/dev/null || g fetch -q --no-tags origin "refs/tags/$2" 2>/dev/null; g cat-file -e "$1^{commit}" 2>/dev/null; }

echo "▶ 发布 $ID@$VER（$KIND）：$D$( [ "$DRY" = 1 ] && echo '  〔dry-run：改动类命令只打印〕')"
HEAD_SHA=""

# ---------- 第 1 步 ----------
step 1 "目录干净、在 main、推送 main"
top="$(g rev-parse --show-toplevel 2>/dev/null)" || fail "不是 Git 仓库"
[ "$top" = "$D" ] || fail "组件目录必须是仓库根目录（brickkit release 才打裸 tag <版本>）：仓库根是 $top"
dirty="$(g status --porcelain)"
[ -z "$dirty" ] || fail "工作区不干净：$(echo "$dirty" | head -5 | tr '\n' ';')"
br="$(g rev-parse --abbrev-ref HEAD)"
[ "$br" = main ] || fail "当前分支是 $br，不是 main"
HEAD_SHA="$(g rev-parse HEAD)"
run g push origin main || fail "git push origin main 失败（不强推；先处理远端分叉）"
if [ "$DRY" = 0 ]; then
  rm_sha="$(g ls-remote origin refs/heads/main | awk '{print $1}')"
  [ "$rm_sha" = "$HEAD_SHA" ] || fail "推送后远端 main 是 ${rm_sha:-空}，不是 HEAD $HEAD_SHA"
fi
pass "HEAD $HEAD_SHA"

# ---------- 第 2 步 ----------
step 2 "契约包 tag（gen/<domain>/<name>/vX，06a N-3）"
CONTRACTS=()
MODULE=""; BASE=""
if [ "$IS_GO" = 0 ]; then
  skip "$KIND 不打契约包 tag"
else
  MODULE="$(awk '$1=="module"{print $2; exit}' "$D/go.mod")"
  if [[ "$MODULE" =~ ^(.*)/v[0-9]+$ ]]; then BASE="${BASH_REMATCH[1]}"; else BASE="$MODULE"; fi
  mapfile -t CONTRACTS < <(awk -v p="$BASE/gen/" '
    /=>/ {next}
    $1=="require" {$1=""; sub(/^ +/, "")}
    index($1, p)==1 && $2 ~ /^v[0-9]/ {print $1, $2}' "$D/go.mod")
  if [ ${#CONTRACTS[@]} -eq 0 ]; then
    skip "根 go.mod 没有 require 本仓库的契约包"
  else
    msgs=()
    for line in "${CONTRACTS[@]}"; do
      pkg="${line% *}"; cver="${line#* }"; sub="${pkg#"$BASE"/}"; tag="$sub/$cver"
      [[ "$cver" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$cver" != v0.0.0 ] \
        || fail "根 go.mod require 的 $pkg $cver 不是一个可发布的契约包版本（占位 v0.0.0 或伪版本）：先让它 require 真实版本（go-v2.sh --recheck）"
      rsha="$(remote_tag_commit "$tag")" || fail "git ls-remote origin 失败"
      if [ -n "$rsha" ]; then
        lsha="$(local_tag_commit "$tag")"
        [ -z "$lsha" ] || [ "$lsha" = "$rsha" ] \
          || fail "本地 tag $tag 指向 $lsha，与已发布的 $rsha 不同——以远端为准；本地这个 tag 是旧尝试或手工打的，核对后人工处理（不自动删）"
        have_commit "$rsha" "$tag" || fail "取不回已发布的 $tag（$rsha）"
        if ! g diff --quiet "$rsha" HEAD -- "$sub"; then
          g diff --stat "$rsha" HEAD -- "$sub" | sed 's/^/    /'
          fail "已发布的契约包 $tag 与 HEAD 的 $sub/ 不一致：已发布的契约包不能改，契约有变化就在根 go.mod require 一个新版本（go-v2.sh --recheck）再发布"
        fi
        msgs+=("$tag 已发布且与 HEAD 一致")
      else
        lsha="$(local_tag_commit "$tag")"
        if [ -n "$lsha" ] && [ "$lsha" != "$HEAD_SHA" ]; then
          fail "本地已有未推送的 $tag，指向 $lsha 而不是 HEAD——不移动，核对后人工处理"
        fi
        [ -n "$lsha" ] || run g tag -a "$tag" -F "$NOTES" HEAD || fail "git tag $tag 失败"
        run g push origin "refs/tags/$tag" || fail "git push origin $tag 失败"
        if [ "$DRY" = 0 ]; then
          [ "$(remote_tag_commit "$tag")" = "$HEAD_SHA" ] || fail "推送后远端 $tag 不在 HEAD"
        fi
        msgs+=("$tag 新打在 HEAD")
      fi
    done
    pass "$(IFS='；'; echo "${msgs[*]}")"
  fi
fi

# ---------- 第 3 步 ----------
step 3 "brickkit release（tag $VER）"
rsha="$(remote_tag_commit "$VER")" || fail "git ls-remote origin 失败"
if [ -n "$rsha" ]; then
  [ "$rsha" = "$HEAD_SHA" ] || fail "远端已有 $VER，指向 $rsha 而不是 HEAD——已推送的 tag 绝不移动；改动要发新版本"
  pass "远端 $VER 已在 HEAD（之前已发布），跳过"
else
  [ -z "$(local_tag_commit "$VER")" ] || fail "本地已有未推送的 tag $VER——brickkit release 会拒绝；核对后人工处理（不自动删除）"
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] brickkit release --notes-file $NOTES   （在 $D 里）"
  else
    echo "  \$ brickkit release --notes-file $NOTES   （在 $D 里）"
    (cd "$D" && brickkit release --notes-file "$NOTES") || fail "brickkit release 失败（推送失败时 brickkit 已删掉本地 tag）"
    [ "$(g cat-file -t "$VER" 2>/dev/null)" = tag ] || fail "git cat-file -t $VER 不是 tag（应为带说明的注解 tag）"
    [ "$(g ls-remote --tags origin "refs/tags/$VER" | wc -l)" -eq 1 ] || fail "git ls-remote --tags origin $VER 没有恰好一行"
    [ "$(remote_tag_commit "$VER")" = "$HEAD_SHA" ] || fail "远端 $VER 不在 HEAD"
  fi
  pass "$( [ "$DRY" = 1 ] && echo 'dry-run：未执行' || echo "注解 tag $VER 已推送、在 HEAD")"
fi

# ---------- 第 4 步 ----------
step 4 "Go 的 v tag（v$VER，与 $VER 同一提交）"
if [ "$IS_GO" = 0 ]; then
  skip "$KIND 只有 $VER"
else
  VT="v$VER"
  rsha="$(remote_tag_commit "$VT")" || fail "git ls-remote origin 失败"
  if [ -n "$rsha" ]; then
    [ "$rsha" = "$HEAD_SHA" ] || fail "远端已有 $VT，指向 $rsha 而不是 HEAD——Go 模块代理会永久缓存 v tag，绝不移动"
  else
    lsha="$(local_tag_commit "$VT")"
    [ -z "$lsha" ] || [ "$lsha" = "$HEAD_SHA" ] || fail "本地已有未推送的 $VT，指向 $lsha 而不是 HEAD——不移动，核对后人工处理"
    [ -n "$lsha" ] || run g tag -a "$VT" -F "$NOTES" HEAD || fail "git tag $VT 失败"
    run g push origin "refs/tags/$VT" || fail "git push origin $VT 失败"
  fi
  if [ "$DRY" = 0 ]; then
    # 以远端为准（新 clone、或上次中断后本地没有 tag 引用时也成立）
    a="$(remote_tag_commit "$VER")"; b="$(remote_tag_commit "$VT")"
    [ "$a" = "$b" ] && [ "$a" = "$HEAD_SHA" ] || fail "远端 $VER→${a:-无}，$VT→${b:-无}，HEAD→$HEAD_SHA：两个 tag 不在同一提交"
    pass "$VER 与 $VT 在同一提交 $HEAD_SHA"
  else
    pass "dry-run：未执行"
  fi
fi

# ---------- 第 5 步 ----------
step 5 "外壳视角拉取探针（go get $MODULE@v$VER + go build）"
if [ "$IS_GO" = 0 ]; then
  skip "$KIND 没有 Go 模块要拉取"
else
  IMPORT=""
  [ -d "$D/backend/module" ] && IMPORT="$MODULE/backend/module"
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] P=\$(mktemp -d) && cd \$P && go mod init probe${IMPORT:+ && main.go: import _ \"$IMPORT\"} && go get $MODULE@v$VER && go build ./... && go list -m all"
    pass "dry-run：未执行"
  else
    want="$( { echo "$MODULE v$VER"; for line in "${CONTRACTS[@]}"; do echo "$line"; done; } | sort)"
    got=""; ok=0
    for ((i = 1; i <= PROBE_RETRIES; i++)); do
      P="$(mktemp -d)"
      if (cd "$P" && export GOWORK=off GOFLAGS=-mod=mod && go mod init probe >/dev/null 2>&1 \
            && { if [ -n "$IMPORT" ]; then printf 'package main\nimport _ "%s"\nfunc main(){}\n' "$IMPORT"; else printf 'package main\nfunc main(){}\n'; fi; } > main.go \
            && go get "$MODULE@v$VER" && go build ./... && go list -m all > modules.txt) > "$P/probe.log" 2>&1; then
        got="$(awk -v b="$BASE" '$1==b || index($1, b"/")==1 {print $1, $2}' "$P/modules.txt" | sort)"
        [ "$got" = "$want" ] && ok=1
      fi
      if [ "$ok" = 1 ]; then rm -rf "$P"; break; fi
      echo "  探针第 $i/$PROBE_RETRIES 次失败：$(tail -3 "$P/probe.log" | tr '\n' ' ')${got:+；go list -m all 里本仓库的模块：$(echo "$got" | tr '\n' ';')}"
      rm -rf "$P"
      [ "$i" -lt "$PROBE_RETRIES" ] && sleep "$PROBE_INTERVAL"
    done
    [ "$ok" = 1 ] || fail "外壳视角拉取/编译失败，或 go list -m all 里本仓库的模块不是恰好：$(echo "$want" | tr '\n' ';')（出现不带 /v2 的 $BASE v1.x.y 就是对着旧契约编译）"
    pass "go list -m all：$(echo "$want" | tr '\n' ';')"
  fi
fi

# ---------- 第 6 步 ----------
step 6 "父仓库要暂存的内容（控制者按路径提交并推送）"
REL="${D#"$ROOT"/}"
echo "  路径：$REL（子模块指针） brickkit.yaml deploy.yaml deploy.teardown.yaml config/$REPO.yaml AGENTS.md"
echo "        （config/vars.yaml、registry/permissions.tsv、registry/data-scopes.tsv 有改动时也带上；不带 .env、.secrets/、deploy.local.yaml、deploy.verify.yaml）"
echo "  git -C $ROOT submodule status $REL 应为：' ${HEAD_SHA:-<HEAD>} $REL ($VER)'$( [ "$IS_GO" = 1 ] && echo "（括号里也可能是 v$VER）")——行首是空格不是 +，没有 -N-g<hash> 后缀"
echo "  git -C $ROOT commit -F <消息文件> -- $REL <上面的项目文件…> && git -C $ROOT log --oneline -1"
pass

echo
if [ "$DRY" = 1 ]; then echo "✓ dry-run 完成：没有推送、打 tag 或调用 brickkit release"; else echo "✓ $ID@$VER 已发布"; fi
