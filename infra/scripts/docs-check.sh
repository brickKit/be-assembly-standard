#!/usr/bin/env bash
# 四份文档的机械检查。内容质量靠 review，这里只查结构（总纲 §4 SOP-D）。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${1:?用法：docs-check.sh <仓库名>  例：docs-check.sh mdm-customer}"
DIR="$ROOT/components/$(echo "$REPO" | sed 's/-/\//')"   # mdm-customer → mdm/customer
FAIL=0
err(){ echo "✗ $*" >&2; FAIL=1; }

need(){ [[ -f "$1" ]] || err "缺文件：$1"; }
need "$ROOT/docs/design/$REPO.md"
need "$DIR/README.md"
need "$DIR/docs/手册.md"
need "$DIR/AGENTS.md"
need "$DIR/CLAUDE.md"

sect(){ # sect <文件> <标题…>
  local f="$1"; shift
  [[ -f "$f" ]] || return
  for t in "$@"; do
    grep -qF "$t" "$f" || err "$f 缺章节：$t"
  done
}
sect "$DIR/README.md" '## 它能做什么' '## 需要哪些基础资源' '## 怎么起来' '## 怎么用' '## 配置项' '## 参考实现' '## 边界与禁令'
sect "$DIR/docs/手册.md" '## 1. 项目结构' '## 2. 功能详解' '## 3. 完整契约清单' '## 4. 数据模型' '## 5. 开发' '## 6. 排障'
sect "$DIR/AGENTS.md" '## 身份证' '## 边界' '## 契约面与事件' '## 依赖与「为什么不依赖某某」' '## 这个组件特有的坑' '## 改代码前的自查'

# CLAUDE.md 必须把 AGENTS.md 接上——Claude Code 只读 CLAUDE.md
grep -qF '@AGENTS.md' "$DIR/CLAUDE.md" 2>/dev/null || err "$DIR/CLAUDE.md 里没有 @AGENTS.md"

# AI 文档硬规则 1：不许有需要回头翻的引用（AI 可能只拿到文件片段，总纲 §4）
grep -nE '见上文|见上节|详见上|如前所述' "$DIR/AGENTS.md" 2>/dev/null && err "$DIR/AGENTS.md 里有「见上文」类引用"

# 设计计划九问
[[ "$(grep -c '^## ' "$ROOT/docs/design/$REPO.md")" -ge 9 ]] \
  || err "docs/design/$REPO.md 的九个二级标题不齐"

for f in "$ROOT/docs/design/$REPO.md" "$DIR/README.md" "$DIR/docs/手册.md" "$DIR/AGENTS.md"; do
  # ⚠️ 曾经只查 'TBD|TODO|待补'，漏了实际写法"（Task N 后补：……）"——4 个
  # 最早建的组件（mdm-product/erp-inventory/erp-finance/erp-sales）的
  # README 里这类占位符存在了很久这条检查却一直显示通过，就是因为正则
  # 没覆盖到真实用的措辞（见 docs/dev/field-tested-pitfalls-log.md）。
  # "后补"必须要求紧跟标点（：或，）才纳入——"后补"本身是常见中文词组的
  # 一部分（"事后补偿""建成后补齐"），裸词匹配会在长篇设计文档里大量
  # 误报，加了这条要求后才用真机跑过一遍全部 14 个组件反向验证过
  [[ -f "$f" ]] && grep -nE 'TBD|TODO|待补|后补[：，]' "$f" && err "$f 里有占位符"
done

((FAIL)) && exit 1
echo "✓ $REPO 四份文档结构完整"
