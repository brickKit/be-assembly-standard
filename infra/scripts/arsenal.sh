#!/usr/bin/env bash
# 军火库自洽闸门。判据刻意抄 brickKit 那份 restore --check 的状态表，
# 官方 brickkit restore 可用时优先委派给它，本地兜底只在它不可用时接管
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
ACTION="${1:-check}"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_OFF=$'\033[0m'

# 短路 1：components/ 还在 .gitignore 里（默认项目）→ 零成本退出
if [[ -z "$(git ls-files --cached -- components/ 2>/dev/null)" ]]; then
  echo "components/ 未被本仓库跟踪，无需检查"; exit 0
fi

# 短路 2：正在 merge/rebase 冲突中 → 放行 + 警告
if [[ -n "$(git ls-files -u 2>/dev/null)" ]]; then
  echo "⚠ 处于合并冲突中，跳过军火库检查"; exit 0
fi

# 短路 3：brickkit 不在 PATH → 放行 + 警告（不能让新人 clone 下来第一件事就提交不了）
if ! command -v brickkit >/dev/null 2>&1; then
  echo "⚠ brickkit 不在 PATH，跳过军火库检查"; exit 0
fi

# 官方命令一旦可用就直接用它，本脚本的判据立即退休
if brickkit restore --help >/dev/null 2>&1; then
  echo "▸ 检测到 brickkit restore，改用官方判据"
  case "$ACTION" in
    check)   exec brickkit restore --check;;
    restore) exec brickkit restore;;
  esac
fi

# ── 以下是 brickkit restore 不可用时的本地兜底实现 ──────────────
# 从 brickkit up --dry-run 拿「这次会启动谁」。CLI 输出里每一行都带理由
if ! plan="$(brickkit up --dry-run 2>/dev/null)"; then
  echo "⚠ brickkit up --dry-run 失败（Manifest 缺失或要联网），跳过检查"; exit 0
fi

# 该跑的组件 ID（形如 mdm/customer）。--dry-run 的行首带组件 ID
mapfile -t SHOULD_RUN < <(printf '%s\n' "$plan" \
  | grep -oP '^\s*\K[a-z0-9-]+/[a-z0-9-]+(?=@)' | sort -u)

FAIL=0; TO_FIX=()
for id in "${SHOULD_RUN[@]}"; do
  active="components/${id}"
  archived="components/.archived/${id}"
  a=0; r=0
  git ls-files --cached --error-unmatch -- "$active"   >/dev/null 2>&1 && a=1
  [[ -d "$active" ]]   && a=1
  [[ -d "$archived" ]] && r=1

  if ((a && r)); then
    echo "${C_RED}✗ ${id}：两处都有源码${C_OFF}"
    echo "   活跃：${active}"
    echo "   归档：${archived}"
    echo "   平台不替你决定保留哪一份——请手工删掉不要的那一份再提交"
    FAIL=1
  elif ((!a && r)); then
    echo "${C_RED}✗ ${id}：brickkit.yaml 说它该启动，但源码在归档目录里${C_OFF}"
    echo "   即将提交的位置：${archived}"
    TO_FIX+=("$id"); FAIL=1
  fi
done

if [[ "$ACTION" == restore ]]; then
  if ((${#TO_FIX[@]})); then
    echo "▸ 跑 brickkit sync 把结构移回活跃目录"
    brickkit sync || exit 1
    echo "${C_GRN}✓ 已还原。请复查 git status 后再提交${C_OFF}"
  else
    echo "${C_GRN}✓ 结构已自洽，无需还原${C_OFF}"
  fi
  exit 0
fi

if ((FAIL)); then
  cat <<'HINT'

两条出路，按你的真实意图选：
  a) 我只是本地聚焦，忘了还原结构  →  make arsenal-restore
  b) 我就是要提交这个归档结构      →  把对应组件的 enabled: false 一起
                                      加进本次提交（那是意图声明，闸门会放行）
  c) 实在要绕                      →  git commit --no-verify（不推荐）
HINT
  exit 1
fi
echo "${C_GRN}✓ 军火库结构与 brickkit.yaml 自洽${C_OFF}"
