#!/usr/bin/env bash
# 核对 PATH 上的 brickkit 是本项目要求的版本；不是就点名二进制路径并退出 2。
#
# 为什么要查：~/go/bin 里还留着旧的 v0.4.6，PATH 把 ~/go/bin 放在前面时它会遮住 ~/.local/bin 的 v1.1.0。
# 旧 CLI 大多大声失败（未知命令），但 ship.sh 的 brickkit release 会照样跑完，发布就交给了旧 CLI，
# 没有任何报错。所以每个会调 brickkit 的入口脚本开头都先过这一关。
#
# 用法：
#   source "$S/lib/require-brickkit.sh"; require_brickkit     （脚本里）
#   bash infra/scripts/lib/require-brickkit.sh                （命令行 / Makefile / env.sh；成功时不输出）
# 要求的版本只写在下面这一处；升级 brickKit 时只改这一行。
BRICKKIT_REQUIRED="BrickKit CLI v1.1.0"

require_brickkit() {
  local bin line
  bin="$(command -v brickkit 2>/dev/null)" || bin=""
  if [ -z "$bin" ]; then
    echo "❌ PATH 上没有 brickkit：本项目要求 $BRICKKIT_REQUIRED（装在 ~/.local/bin/brickkit）" >&2
    exit 2
  fi
  # 旧版本会往 stderr 打 JSON 日志：只看 stdout 里第一行 "BrickKit CLI …"。
  # 先把输出整个读完再匹配：管道里接 grep -m1 时，grep 匹配后就关掉管道，brickkit
  # 写下一行时被 SIGPIPE 杀掉，pipefail 下整条管道失败，已匹配的版本行被丢掉。
  local out
  out="$(brickkit version 2>/dev/null)" || out=""
  line="$(printf '%s\n' "$out" | awk '/^BrickKit CLI /{print; exit}')"
  if [ "$line" != "$BRICKKIT_REQUIRED" ]; then
    echo "❌ PATH 上的 brickkit 是 $bin：${line:-brickkit version 没有输出 BrickKit CLI 版本行}；本项目要求 $BRICKKIT_REQUIRED" >&2
    echo "   多半是 ~/go/bin 排在 ~/.local/bin 前面：export PATH=\$PATH:\$HOME/go/bin（追加，不前置），再 command -v brickkit 核对" >&2
    exit 2
  fi
}

# 直接执行（不是 source）时做一次检查
if [ "${BASH_SOURCE[0]}" = "$0" ]; then require_brickkit; fi
