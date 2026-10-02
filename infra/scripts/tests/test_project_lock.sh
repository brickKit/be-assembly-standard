#!/usr/bin/env bash
# project-lock.sh 的测试：串行、嵌套不死锁、超时报持有者、持有者崩溃后锁自动回收。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCK_SH="$ROOT/infra/scripts/project-lock.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export BE_PROJECT_LOCK="$T/lock"
unset BE_PROJECT_LOCK_HELD
fail=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1" >&2; fail=1; }

# 1. 两个进程同时拿锁：区间不重叠
slow='echo "start $$ $(date +%s.%N)" >> '"$T"'/log; sleep 1; echo "end $$ $(date +%s.%N)" >> '"$T"'/log'
bash "$LOCK_SH" -- bash -c "$slow" >/dev/null & p1=$!
bash "$LOCK_SH" -- bash -c "$slow" >/dev/null & p2=$!
wait $p1 $p2
if [ "$(awk '{print $1}' "$T/log" | tr '\n' ' ')" = "start end start end " ]; then ok "两个并发进程串行执行"; else bad "并发区间重叠: $(cat "$T/log")"; fi

# 2. 持锁进程里嵌套调用不死锁，并且命令的退出码原样返回
out="$(timeout 20 bash "$LOCK_SH" -- bash -c "bash '$LOCK_SH' -- bash -c 'exit 7'" 2>&1)"; rc=$?
if [ $rc -eq 7 ]; then ok "嵌套调用不死锁、退出码透传"; else bad "嵌套 rc=$rc: $out"; fi

# 3. 超时：非零退出并打印持有者
bash "$LOCK_SH" -- bash -c 'sleep 4' >/dev/null 2>&1 & holder=$!
sleep 0.5
out="$(BE_PROJECT_LOCK_TIMEOUT=1 bash "$LOCK_SH" -- true 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q "sleep 4"; then ok "超时非零退出并点名持有者"; else bad "超时 rc=$rc out=$out"; fi
wait $holder

# 4. 持有者被 kill -9 后，锁自动回收
bash "$LOCK_SH" -- bash -c 'sleep 30' >/dev/null 2>&1 & holder=$!
sleep 0.5
pkill -9 -f "sleep 30"; kill -9 $holder 2>/dev/null; wait $holder 2>/dev/null
out="$(BE_PROJECT_LOCK_TIMEOUT=5 timeout 20 bash "$LOCK_SH" -- echo recovered 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q recovered; then ok "崩溃持有者的陈旧锁被回收"; else bad "回收 rc=$rc out=$out"; fi

[ $fail -eq 0 ] && echo "PASS" || { echo "FAILED" >&2; exit 1; }
