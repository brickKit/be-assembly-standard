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
fake 'echo "BrickKit CLI v1.4.1"; sleep 0.3; echo "Supported Manifest version: brickkit/v1"; echo more'
expect 0 "正确版本、版本行之后慢慢再写几行 → 放行"
fake 'echo "BrickKit CLI v0.4.6"'
expect 2 "旧版本 → 拒绝"
fake 'echo "BrickKit CLI v1.3.1"'
expect 2 "更早要求的版本 v1.3.1 → 拒绝（release.checks 要 v1.4.0）"
fake 'echo "BrickKit CLI v1.4.0"'
expect 2 "上一个要求的版本 v1.4.0 → 拒绝（检查跑完不再核对组件目录，要 v1.4.1）"
fake 'echo "{\"level\":\"info\"}" >&2; echo "BrickKit CLI v1.4.1"'
expect 0 "stderr 有日志、stdout 版本对 → 放行"
fake 'exit 1'
expect 2 "brickkit version 失败 → 拒绝"
[ $fail = 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
