#!/usr/bin/env bash
# lib/require-brickkit.sh：版本对放行、不对拒绝；版本行之后还有输出且写得慢时也不误拒
# （曾经用 grep -m1 接管道：grep 先退出，brickkit 写下一行时被 SIGPIPE 杀掉，pipefail 下误判）。
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib/require-brickkit.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
fake() { printf '#!/bin/sh\n%s\n' "$1" > "$T/brickkit"; chmod +x "$T/brickkit"; }
expect() { # <期望退出码> <说明>
  # 和入口脚本一样：set -euo pipefail 下 source 再调用
  PATH="$T:$PATH" LIB="$LIB" bash -c 'set -euo pipefail; source "$LIB"; require_brickkit' >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$1" ]; then echo "ok   $2"; else echo "FAIL $2（rc=$rc，期望 $1）"; fail=1; fi
}
fake 'echo "BrickKit CLI v1.8.4"; sleep 0.3; echo "Supported Manifest version: brickkit/v1"; echo more'
expect 0 "正确版本、版本行之后慢慢再写几行 → 放行"
fake 'echo "BrickKit CLI v0.4.6"'
expect 2 "旧版本 → 拒绝"
fake 'echo "BrickKit CLI v1.3.1"'
expect 2 "更早要求的版本 v1.3.1 → 拒绝（release.checks 要 v1.4.0）"
fake 'echo "BrickKit CLI v1.4.0"'
expect 2 "更早要求的版本 v1.4.0 → 拒绝（检查跑完不再核对组件目录，要 v1.4.1）"
fake 'echo "BrickKit CLI v1.4.1"'
expect 2 "更早要求的版本 v1.4.1 → 拒绝（local 的三种跑法与重复键的报错在 v1.4.2）"
fake 'echo "BrickKit CLI v1.4.2"'
expect 2 "更早要求的版本 v1.4.2 → 拒绝（重发版本报 VERSION_CHANGED、写 repo 的安装源在 v1.5.0）"
fake 'echo "BrickKit CLI v1.5.0"'
expect 2 "更早要求的版本 v1.5.0 → 拒绝（只写 image 的组件改为拉取、build 报出本地仓库的版本在 v1.6.0）"
fake 'echo "BrickKit CLI v1.6.0"'
expect 2 "更早要求的版本 v1.6.0 → 拒绝（up 对只写 image、旁边有 Dockerfile 的组件给出警告在 v1.6.1）"
fake 'echo "BrickKit CLI v1.6.1"'
expect 2 "更早要求的版本 v1.6.1 → 拒绝（local.migrationCommand 与本机进程的端口检查在 v1.7.0）"
fake 'echo "BrickKit CLI v1.7.0"'
expect 2 "更早要求的版本 v1.7.0 → 拒绝（本机外壳的成员从源码迁移在 v1.7.1）"
fake 'echo "BrickKit CLI v1.7.1"'
expect 2 "更早要求的版本 v1.7.1 → 拒绝（外壳成员的地址写成员自己的服务名在 v1.7.2）"
fake 'echo "BrickKit CLI v1.7.2"'
expect 2 "更早要求的版本 v1.7.2 → 拒绝（Docker、Podman 下的 replicas 在 v1.8.0）"
fake 'echo "BrickKit CLI v1.8.0"'
expect 2 "更早要求的版本 v1.8.0 → 拒绝（status、down 的 Podman socket 提示在 v1.8.1）"
fake 'echo "BrickKit CLI v1.8.1"'
expect 2 "更早要求的版本 v1.8.1 → 拒绝（两个外壳编进同一组成员时的升级在 v1.8.2，FRB-006）"
fake 'echo "BrickKit CLI v1.8.2"'
expect 2 "更早要求的版本 v1.8.2 → 拒绝（升级外壳不加回使用者移除的成员在 v1.8.3，FRB-007）"
fake 'echo "BrickKit CLI v1.8.3"'
expect 2 "上一个要求的版本 v1.8.3 → 拒绝（移除过的成员因强依赖加回时的提示、升级报出新配置在 v1.8.4，FRR-007）"
fake 'echo "{\"level\":\"info\"}" >&2; echo "BrickKit CLI v1.8.4"'
expect 0 "stderr 有日志、stdout 版本对 → 放行"
fake 'exit 1'
expect 2 "brickkit version 失败 → 拒绝"
[ $fail = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
