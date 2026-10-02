#!/usr/bin/env bash
# 第 2 步：拿 brickKit v1 骨架，给组件写出文档骨架（四件套 + docs/design.md，各带 .zh.md），旧文件留底。
#
# 用法：bash dev/phase-06/tools/docs-skel.sh <scope>/<name> [--force]
#   BE_SCRATCH 必填（见 env.sh）；BE_COMP_DIR 可改组件目录。
# 做什么：
#   1. rm -rf $S/skel && brickkit new <id> --path $S/skel
#   2. 留底到 $S/old/：AGENTS.md README.md CLAUDE.md docs/手册.md component.yaml assembly.yaml Makefile Dockerfile
#      **取自组件最后一个 1.x tag**（git show <tag>:<文件>），与工作区、与会话无关：换会话、清空 $S 后留底不变
#   3. 写出 BRICKKIT.md AGENTS.md README.md（取骨架；后两个加首行互链）及其 .zh.md（固定中文标题、首行互链、正文待填），
#      docs/design.md + .zh.md（component-loop 5.1 的 design 小节），CLAUDE.md 恰好 `@AGENTS.md`
# 覆盖规则：目标文件不存在、与将写出的内容相同、或与 tag 上的同名文件相同（即还没人动过）时才写；
#   否则（已经填写过）跳过并提示，--force 才覆盖。判断不依赖 $S，所以换会话重跑也不会覆盖已填写的文档。
#   CLAUDE.md 例外：总是写成恰好 `@AGENTS.md`。
# 骨架与 .zh.md 里的 `<!-- TODO … -->` 会被 brickkit lint 报 DOC_PLACEHOLDER——这是第 5 步（C5）要填的。
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
die() { echo "❌ docs-skel.sh: $*" >&2; exit 2; }

ID=""; FORCE=0
for a in "$@"; do
  case $a in
    --force) FORCE=1 ;;
    -*) die "不认识的参数 $a" ;;
    *) [ -z "$ID" ] && ID=$a || die "多余的参数 $a" ;;
  esac
done
[ -n "$ID" ] || die "用法：bash docs-skel.sh <scope>/<name> [--force]"
envout=$(bash "$HERE/env.sh" "$ID") || exit 2
eval "$envout"

echo "📄 $ID：文档骨架（组件目录 $C，临时目录 $S）"

# ── 1. 骨架 ──
rm -rf "$S/skel"
( cd "$S" && brickkit new "$ID" --path "$S/skel" ) >"$S/brickkit-new.log" 2>&1 || { cat "$S/brickkit-new.log" >&2; die "brickkit new 失败"; }
for f in BRICKKIT.md AGENTS.md CLAUDE.md README.md component.yaml; do
  [ -s "$S/skel/$f" ] || { cat "$S/brickkit-new.log" >&2; die "brickkit new 没有生成 $f"; }
done
[ "$(cat "$S/skel/CLAUDE.md")" = "@AGENTS.md" ] || die "骨架的 CLAUDE.md 不是 @AGENTS.md（brickKit 行为变了？）"
grep -q 'brickkit:managed:begin' "$S/skel/AGENTS.md" || die "骨架的 AGENTS.md 没有 brickkit 维护块（brickKit 行为变了？）"
echo "  ✅ brickkit new $ID --path $S/skel"

# ── 2. 留底（取自最后一个 1.x tag） ──
TAG=$(git -C "$C" tag -l '1.*' 'v1.*' | grep -E '^v?1\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[ -n "$TAG" ] || die "$C 没有任何 1.x tag，无法判断哪些文档还没被动过"
at_tag() { git -C "$C" cat-file -e "$TAG:$1" 2>/dev/null; }      # tag 上有没有这个文件
mkdir -p "$S/old"
for rel in AGENTS.md README.md CLAUDE.md docs/手册.md component.yaml assembly.yaml Makefile Dockerfile; do
  dst=$S/old/$(basename "$rel")
  at_tag "$rel" || continue
  git -C "$C" show "$TAG:$rel" >"$dst.tmp" || die "git show $TAG:$rel 失败"
  if [ -e "$dst" ] && cmp -s "$dst" "$dst.tmp"; then rm -f "$dst.tmp"; echo "  ·  留底已是 $TAG:$rel"
  else mv "$dst.tmp" "$dst"; echo "  📦 留底 $TAG:$rel → $dst"; fi
done

# ── 3. 生成要写出的内容 ──
G=$S/skel-gen; rm -rf "$G"; mkdir -p "$G/docs"
link() { printf '[English](%s.md) · [中文](%s.zh.md)\n\n' "$1" "$1"; }
todo_zh='<!-- TODO: 待填 -->'

cp "$S/skel/BRICKKIT.md" "$G/BRICKKIT.md"             # BRICKKIT*.md 不写任何相对链接（含互链行）
{ link AGENTS; cat "$S/skel/AGENTS.md"; } >"$G/AGENTS.md"
{ link README; sed "s#brickkit add $ID@[0-9.]*#brickkit add $ID@2.0.0#" "$S/skel/README.md"; } >"$G/README.md"
cp "$S/skel/CLAUDE.md" "$G/CLAUDE.md"

{
  printf '# %s\n' "$ID"
  for h in 组件定位 部署前准备 依赖说明 配置指南 契约索引; do printf '\n## %s\n\n%s\n' "$h" "$todo_zh"; done
  printf '\n## 外壳声明\n\n不是外壳。\n'
} >"$G/BRICKKIT.zh.md"
{
  link AGENTS; printf '# %s\n\n开发本组件的 AI 指南。用法、边界与契约：BRICKKIT.md；依赖、配置与部署：component.yaml。\n' "$ID"
  for h in 代码地图 构建与测试 设计取舍 易错点 改代码前自查; do printf '\n## %s\n\n%s\n' "$h" "$todo_zh"; done
} >"$G/AGENTS.zh.md"
{
  link README; printf '# %s\n\n%s\n' "$ID" '<!-- TODO: 待填（与 metadata.description 同一句话） -->'
  printf '\n## 在项目里使用\n\n```bash\nbrickkit add %s@2.0.0\nbrickkit up\n```\n\n先看 BRICKKIT.md 的"部署前准备"。\n' "$ID"
  for h in 文档 开发; do printf '\n## %s\n\n%s\n' "$h" "$todo_zh"; done
} >"$G/README.zh.md"

# docs/design.md：component-loop 5.1 的 design 一行，只写结论
DESIGN_EN=(
  "Boundaries|what this component owns, and what it explicitly does not (saying who owns it)"
  "Owned data|tables, partitions, terminal states"
  "Contract surface|rpcs (including batchGet), REST paths with their permission keys, idempotent endpoints, status endpoints"
  "Events|events published and consumed"
  "Dependencies|each dependency and what it is used for; why it does not depend on a component one might expect"
  "Place in the synchronous call graph|who calls it, whom it calls"
  "Partitioning and archiving|which tables are partitioned, how and when rows are archived"
  "Data scopes|the row-level scopes and their operands, or why there are none"
  "Reference implementations|which open-source implementations were read, and for what"
  "Open questions|what is not decided yet"
)
DESIGN_ZH=(边界 拥有的数据 契约面 发布与消费的事件 依赖 在同步调用图里的位置 分区与归档 数据范围 参考实现 未决问题)
{
  link design; printf '# %s design\n' "$ID"
  for row in "${DESIGN_EN[@]}"; do printf '\n## %s\n\n<!-- TODO: %s -->\n' "${row%%|*}" "${row#*|}"; done
} >"$G/docs/design.md"
{
  link design; printf '# %s 设计\n' "$ID"
  for h in "${DESIGN_ZH[@]}"; do printf '\n## %s\n\n%s\n' "$h" "$todo_zh"; done
} >"$G/docs/design.zh.md"

# 自检：每对文件 ## 小节数一致（AGENTS.md 的维护块不算）
sections() { sed '/brickkit:managed:begin/,$d' "$1" | grep -c '^## ' || true; }
for f in BRICKKIT AGENTS README docs/design; do
  [ "$(sections "$G/$f.md")" = "$(sections "$G/$f.zh.md")" ] || die "$f.md 与 $f.zh.md 的 ## 小节数不一致（骨架变了？）：$(sections "$G/$f.md") vs $(sections "$G/$f.zh.md")"
done

# ── 4. 写出 ──
SKIPPED=0; CHANGED=0
place() {  # place <相对路径>
  local rel=$1 src=$G/$1 dst=$C/$1
  mkdir -p "$(dirname "$dst")"
  if [ ! -e "$dst" ]; then cp "$src" "$dst"; echo "  ✏️  新建 $rel"; CHANGED=$((CHANGED+1))
  elif cmp -s "$src" "$dst"; then echo "  ·  未改动 $rel"
  elif [ $FORCE = 1 ]; then cp "$src" "$dst"; echo "  ✏️  覆盖 $rel（--force）"; CHANGED=$((CHANGED+1))
  elif at_tag "$rel" && git -C "$C" show "$TAG:$rel" | cmp -s - "$dst"; then
    cp "$src" "$dst"; echo "  ✏️  用骨架替换 $rel（与 $TAG 上的原文相同，还没人动过；原文已留底）"; CHANGED=$((CHANGED+1))
  else echo "  ⚠️  跳过 $rel：已有内容（既不是骨架也不是 $TAG 上的原文），要覆盖加 --force"; SKIPPED=$((SKIPPED+1))
  fi
}
for rel in BRICKKIT.md BRICKKIT.zh.md AGENTS.md AGENTS.zh.md README.md README.zh.md docs/design.md docs/design.zh.md; do place "$rel"; done
if [ -e "$C/CLAUDE.md" ] && cmp -s "$G/CLAUDE.md" "$C/CLAUDE.md"; then echo "  ·  未改动 CLAUDE.md"
else cp "$G/CLAUDE.md" "$C/CLAUDE.md"; echo "  ✏️  CLAUDE.md 写成恰好 @AGENTS.md"; CHANGED=$((CHANGED+1)); fi

echo "✅ docs-skel：改动 $CHANGED 个文件，跳过 $SKIPPED 个（跳过的是已经填写过的文件）"
[ -e "$C/docs/手册.md" ] && echo "   下一步：git -C $C rm -q docs/手册.md（已留底），然后 (cd $C && brickkit skills update)"
exit 0
