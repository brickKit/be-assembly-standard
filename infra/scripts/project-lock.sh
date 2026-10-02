#!/usr/bin/env bash
# 项目锁：并行实施者不会同时跑 brickkit add/up/build 或改共享的项目文件。
# 用法：bash infra/scripts/project-lock.sh -- <命令…>
#   环境变量：BE_PROJECT_LOCK（锁文件，默认 /tmp/be-assembly-standard.project.lock）
#            BE_PROJECT_LOCK_TIMEOUT（总等待秒数，默认 3600）
#            BE_PROJECT_LOCK_REPORT（等锁时多久点名一次持有者，默认 60 秒）
# 持锁期间导出 BE_PROJECT_LOCK_HELD=1：子进程再调用本脚本（或自带锁的 make 目标）时直接执行。
# 锁是内核级 flock：持有者崩溃/被 kill 后自动释放，不会留下陈旧锁。
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
# 不让子进程继承锁 fd：后台遗留进程不应让锁一直占着
"$@" 9>&-
rc=$?
: > "$LOCK"
exit $rc
