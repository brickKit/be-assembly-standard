#!/usr/bin/env bash
# 阶段四 Task 10：设计书 §13.7 拆回门禁的"每周自动跑一次"那一半——
# "确实有一个每周自动跑一次拆回门禁的机制，而不是只在改动合并组关系时
# 手动跑"。本脚本不装 crontab（改宿主机的 crontab 是持久的系统级改动，
# 留给部署人员自己决定要不要装），只提供一条可重复运行、幂等、失败也不
# 留残留状态的验证流程——文件末尾的注释给出真实的 crontab 配置行。
#
# 判据同 §13.7 原文："这条门禁的失败不代表独立部署有 bug，代表合并那一
# 刻磨掉了组件性"——失败时优先怀疑铁律六（有人 import 了别人）或铁律二
# （有人跨 schema 查了），不是去怀疑业务逻辑本身。
#
# 流程：① 确认 git 工作区干净（不干净直接中止，不清理别人的在制品）
# ② 无条件停掉外壳态 + 全拆态的全部容器（同 make shell-up/teardown-up
# 的既有判据："图简单直接全关，不判断是不是真的有冲突"）③ brickkit.yaml
# 临时去掉全部 local:true/localPort（内存里改，从不 commit）④ brickkit up
# 起 14 个组件各自独立的容器 ⑤ make tier0 + make tier1 ⑥ 不管成功失败，
# 用 git checkout 把 brickkit.yaml 恢复成拆之前提交的样子 ⑦ brickkit down
# 收尾，不尝试猜测"该不该把外壳态重新起回来"——组装态容器默认关闭是本
# 项目自己的既有习惯（AGENTS.md），不替不在场的人做假设。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_OFF=$'\033[0m'
ok()   { echo "${C_GRN}✓${C_OFF} $*"; }
warn() { echo "${C_YLW}⚠${C_OFF} $*"; }
die()  { echo "${C_RED}✗${C_OFF} $*" >&2; exit 1; }

echo "▸ 阶段四 Task 10 · 拆回门禁 · $(date -Iseconds)"

[[ -f brickkit.yaml ]] || die "找不到 brickkit.yaml，脚本没跑在装配仓库根目录？"

if [[ -n "$(git status --porcelain)" ]]; then
  die "git 工作区不干净——拆回门禁只能在干净的工作区上跑（怕的是这条脚本 checkout 掉别人还没提交的改动）。先 commit/stash，再重跑。"
fi

echo "▸ 停掉外壳态 + 全拆态的全部容器（不判断是不是真的有冲突，图简单直接全关）"
docker compose --env-file .env -p be-shell -f infra/shell-compose.yml down >/dev/null 2>&1 || true
brickkit down >/dev/null 2>&1 || true

echo "▸ 临时去掉 brickkit.yaml 里全部 local:true/localPort（不 commit，结束时原样恢复）"
python3 - << 'PYEOF'
import re
with open("brickkit.yaml", encoding="utf-8") as f:
    content = f.read()
pattern = re.compile(
    r"[ \t]*# ⚠️ local: true 不是有人在调试，是合并部署（阶段四 Task [67] 原子式切换，设计书 §13\.1）\n"
    r"[ \t]*local: true\n"
    r"[ \t]*localPort: \d+\n"
)
new_content, n = pattern.subn("", content)
with open("brickkit.yaml", "w", encoding="utf-8") as f:
    f.write(new_content)
print(f"  去掉了 {n} 处 local: true")
PYEOF

restore_and_exit() {
  code="$1"
  echo "▸ 恢复 brickkit.yaml 到拆之前提交的样子"
  git checkout -- brickkit.yaml
  echo "▸ 停掉这次验证起的全部独立容器（组装态容器默认关闭，不替你猜要不要重新起外壳）"
  brickkit down >/dev/null 2>&1 || true
  if [[ "$code" -eq 0 ]]; then
    ok "拆回门禁通过：$(date -Iseconds)"
  else
    echo "${C_RED}✗ 拆回门禁失败：$(date -Iseconds)——先怀疑铁律六（import 了别人）或铁律二（跨 schema 查了），不是业务逻辑本身${C_OFF}" >&2
  fi
  exit "$code"
}

echo "▸ brickkit up：11 个 Go 组件 + infra/print 各自独立起一个容器"
if ! brickkit up; then
  restore_and_exit 1
fi

echo "▸ make tier0（档 0 六项验收）"
if ! make tier0; then
  restore_and_exit 1
fi

echo "▸ make tier1（档 1 平台断言）"
if ! make tier1; then
  restore_and_exit 1
fi

restore_and_exit 0

# ────────────────────────────────────────────────────────────────
# 真实的 crontab 配置行（本脚本不会替你装，安全起见由部署人员自己决定
# 要不要启用）——每周日凌晨 3 点跑一次，日志追加写：
#
#   0 3 * * 0 cd /path/to/be-assembly-standard && ./infra/scripts/weekly-teardown-gate.sh >> /var/log/weekly-teardown-gate.log 2>&1
#
# 装之前确认：① 这台机器上 brickkit/docker/make 都在 cron 的 PATH 里
# （cron 默认 PATH 比交互 shell 窄很多，建议在 crontab 里显式设
# PATH=/usr/local/bin:/usr/bin:/bin 或写绝对路径）；② .env 里的密码在这台
# 机器上是真实可用的（这条脚本会真的起 14 个容器）；③ 这台机器同一时刻
# 没有别人在用外壳态或全拆态部署做别的事——本脚本会无条件停掉两边的
# 容器，这在一台共享的开发机上可能是破坏性的，生产/CI 专用机器上没有
# 这个顾虑。
