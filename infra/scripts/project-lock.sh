#!/usr/bin/env bash
# 项目锁：并行实施者不会同时跑 brickkit add/up/build 或改共享的项目文件。
# 用法：bash infra/scripts/project-lock.sh -- <命令…>
#   环境变量：BE_PROJECT_LOCK（锁文件，默认 /tmp/be-assembly-standard.project.lock）
#            BE_PROJECT_LOCK_TIMEOUT（总等待秒数，默认 3600）
#            BE_PROJECT_LOCK_REPORT（等锁时多久点名一次持有者，默认 60 秒）
# 持锁期间导出 BE_PROJECT_LOCK_HELD=1：子进程再调用本脚本（或自带锁的 make 目标）时直接执行。
# 锁是内核级 flock：持有者崩溃/被 kill -9 后自动释放，不会留下陈旧锁。
# INT/TERM/HUP 转发给子命令，等它退出后才释放锁；退出码是子命令的（被信号杀死时 128+信号）。
set -uo pipefail
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "用法：project-lock.sh -- <命令…>" >&2; exit 2; }

if [ -n "${BE_PROJECT_LOCK_HELD:-}" ]; then exec "$@"; fi

LOCK="${BE_PROJECT_LOCK:-/tmp/be-assembly-standard.project.lock}"
TIMEOUT="${BE_PROJECT_LOCK_TIMEOUT:-3600}"
REPORT="${BE_PROJECT_LOCK_REPORT:-60}"
exec 9>>"$LOCK"
chmod 666 "$LOCK" 2>/dev/null || true

waited=0
while ! flock -w "$(( REPORT < TIMEOUT - waited ? REPORT : TIMEOUT - waited ))" 9; do
  waited=$(( waited + (REPORT < TIMEOUT - waited ? REPORT : TIMEOUT - waited) ))
  echo "⏳ project lock held by: $(cat "$LOCK" 2>/dev/null)（已等 ${waited}s）" >&2
  if [ "$waited" -ge "$TIMEOUT" ]; then
    echo "✗ 等待项目锁超时（${TIMEOUT}s），持有者：$(cat "$LOCK" 2>/dev/null)" >&2
    exit 1
  fi
done
printf 'pid=%s cmd=%s\n' "$$" "$*" > "$LOCK"
echo "🔒 project lock acquired by $$ ($*)" >&2

export BE_PROJECT_LOCK_HELD=1
# 子进程在后台跑、本进程 wait 它：收到 INT/TERM/HUP 时转发给子进程并继续等，子进程真正退出后才释放锁——
# 只 kill 包装进程（timeout、kill <pid>）不会让锁在子命令还在改项目状态时提前放掉。
#   - 不让子进程继承锁 fd 9：后台遗留进程不应让锁一直占着
#   - 非交互 shell 的后台进程默认忽略 INT/QUIT、标准输入接 /dev/null：用 env 恢复默认信号处理，
#     fd 8 把本进程的标准输入原样交给子进程（交互式提问、管道照常）
#   - 终端里 Ctrl+C 本来就发给整个前台进程组，子进程会再收到一次转发的 INT
child=""
forward() { [ -n "$child" ] && kill -"$1" "$child" 2>/dev/null; return 0; }
trap 'forward INT' INT
trap 'forward TERM' TERM
trap 'forward HUP' HUP
{ exec 8<&0; } 2>/dev/null || exec 8</dev/null   # 标准输入已关闭时给子进程 /dev/null（花括号让 2> 只作用于这一句）
env --default-signal=INT,QUIT "$@" <&8 8<&- 9>&- &
child=$!
exec 8<&-
while :; do
  wait "$child"; rc=$?
  kill -0 "$child" 2>/dev/null || break      # wait 被转发的信号打断时子进程还活着：接着等
done
: > "$LOCK"
exit $rc                                     # 子进程的退出码；被信号杀死时是 128+信号
