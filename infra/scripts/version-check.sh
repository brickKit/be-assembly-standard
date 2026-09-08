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
#
# 顺带守一条相邻的坑：HEAD 上的 tag 必须是**带注解的**（`git tag -a`），
# 不能是轻量 tag（`git tag vX.Y.Z`）。`git submodule status` 内部用不带
# `--tags` 的 `git describe`，只认带注解的 tag——如果 HEAD 是轻量 tag、
# 而历史上更早处恰好有一个带注解的 tag，`git submodule status` 会静默
# 报出那个更早的 tag 加一截 `-N-g<hash>`（这条脚本自己用 `--tags` 所以
# 看不出异常，只有 `git submodule status` 会显得像是"漂移"）——infra-authz
# 建仓库时用 `git submodule add` 挂载已有仓库，核对 `git submodule status`
# 才真的撞见 tools/be-sdk-go 卡在这个状态（v0.1.8/v0.1.9 当时打成了轻量
# tag）。带注解的 tag 用 `git cat-file -t <tag>` 会返回 `tag`，轻量 tag
# 返回 `commit`。
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
    continue
  fi
  tagtype="$(git -C "$p" cat-file -t "$desc" 2>&1)"
  if [[ "$tagtype" != "tag" ]]; then
    echo "${C_RED}✗ $p：$desc 是轻量 tag（应为带注解的 \`git tag -a\`）——git submodule status 会显得像是漂移${C_OFF}"
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
