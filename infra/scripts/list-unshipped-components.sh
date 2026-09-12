#!/usr/bin/env bash
# 列出"HEAD 已经领先最新 tag"的组件仓库，连同这段时间的 commit 摘要——
# 给 version-bump-ship 技能（.claude/skills/version-bump-ship/）当第一步
# 用：判断"这次真的动过、该发布"的组件都有哪些，不用凭记忆或者一个个
# 手动 git status。
#
# 跟 infra/scripts/version-check.sh 用的是同一条判据（HEAD 领先 tag =
# 有已提交但没打版本号 tag 的改动），但目的不同：那份脚本把这当成
# **该修的漂移**（门禁，红了要拦下 CI）；这份脚本把它当成**该核对的
# 候选**（发现工具，纯打印，永远 exit 0，不拦任何东西）——同一个信号，
# 一个当"必须马上处理的报警"，一个当"这里有情况，你自己判断"。
#
# ⚠️ 列出来的不代表都该在这次一起发布——可能混着这次任务范围之外、
# 别的工作留下的半成品提交，需要人/AI 逐条判断，不能全盘照单发布。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

C_YEL=$'\033[33m'; C_OFF=$'\033[0m'

if [[ ! -f .gitmodules ]]; then
  echo "没有 .gitmodules，无组件仓库可检查"
  exit 0
fi

mapfile -t paths < <(git config -f .gitmodules --get-regexp '\.path$' | awk '{print $2}')

found=0
for p in "${paths[@]}"; do
  [[ "$p" == components/* ]] || continue   # 只关心组件仓库，工具仓库（tools/*）不走这条发布节奏
  if [[ ! -d "$p/.git" && ! -f "$p/.git" ]]; then
    continue
  fi

  desc="$(git -C "$p" describe --tags 2>/dev/null)"
  if [[ -z "$desc" ]]; then
    echo "${C_YEL}⚠ $p：从没打过 tag，全部提交都算候选${C_OFF}"
    git -C "$p" log --format='    - %s' | head -20
    found=1
    continue
  fi
  if [[ ! "$desc" =~ -([0-9]+)-g[0-9a-f]+$ ]]; then
    continue   # HEAD 就是最新 tag 本身，没有未发布的改动
  fi

  lasttag="$(git -C "$p" describe --tags --abbrev=0 2>/dev/null)"
  echo "${C_YEL}⚠ $p：HEAD 领先 $lasttag，未发布的提交：${C_OFF}"
  git -C "$p" log "${lasttag}..HEAD" --format='    - %s'
  found=1
done

if [[ $found -eq 0 ]]; then
  echo "没有组件仓库处于「HEAD 领先最新 tag」的状态——没有待发布的候选"
fi
