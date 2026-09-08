#!/usr/bin/env bash
# 版本漂移检查（阶段三 Task 3，阶段二复盘 §4 第 1 条留的决定：加）。
#
# 判据：任何登记为 submodule 的仓库，如果 `git describe --tags` 的结果带
# `-N-g<hash>` 后缀（N>0），说明 HEAD 已经领先最新 tag——有已提交但没打
# tag 的改动。阶段二真的因为这条纪律单靠约定而漂移过三个仓库
# （mdm-customer/mdm-product/erp-inventory 升级 be-sdk-go 依赖后忘了打新
# tag），机械化检查比指望人记住更可靠。
#
# 完全没有 tag（`git describe` 直接 fatal）也算漂移——阶段三写这个脚本时
# 真的抓到过 be-sdk-python/be-sdk-ts 建仓库后忘了打 v0.1.0 的情况。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_OFF=$'\033[0m'

if [[ ! -f .gitmodules ]]; then
  echo "✓ 没有 .gitmodules，无需检查"
  exit 0
fi

# 用 git config -f .gitmodules 而不是自己 grep/awk 解析——.gitmodules
# 本来就是一份 git config 格式文件，官方解析器不会被将来加的字段（如
# submodule.<name>.branch）带偏。
mapfile -t paths < <(git config -f .gitmodules --get-regexp '\.path$' | awk '{print $2}')

if [[ ${#paths[@]} -eq 0 ]]; then
  echo "✓ .gitmodules 里没有登记任何 submodule"
  exit 0
fi

bad=0
for p in "${paths[@]}"; do
  if [[ ! -d "$p/.git" && ! -f "$p/.git" ]]; then
    echo "⚠ $p 尚未 checkout（submodule init 未跑），跳过"
    continue
  fi
  desc="$(git -C "$p" describe --tags 2>&1)"
  if [[ $? -ne 0 ]]; then
    echo "${C_RED}✗ $p：没有任何 tag（$desc）${C_OFF}"
    bad=1
    continue
  fi
  if [[ "$desc" =~ -[0-9]+-g[0-9a-f]+$ ]]; then
    echo "${C_RED}✗ $p：HEAD 领先最新 tag（$desc）——有已提交但没打 tag 的改动${C_OFF}"
    bad=1
  else
    echo "${C_GRN}✓ $p：$desc${C_OFF}"
  fi
done

if [[ $bad -ne 0 ]]; then
  echo
  echo "${C_RED}版本漂移检查未通过：给上面 ✗ 的仓库打新 tag 并 push${C_OFF}" >&2
  exit 1
fi
echo
echo "${C_GRN}✓ 全部 submodule HEAD 与最新 tag 一致${C_OFF}"
