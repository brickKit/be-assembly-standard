#!/usr/bin/env bash
# project-lock.sh 的测试：串行、嵌套不死锁、超时报持有者、持有者崩溃后锁自动回收、信号转发与退出码、标准输入透传。
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
# 只杀这一棵进程树（pkill -f 会误杀命令行里恰好含同样文字的其它进程，包括调用本测试的 shell）
kids="$(pgrep -P $holder)"; kill -9 $holder $kids 2>/dev/null; wait $holder 2>/dev/null
out="$(BE_PROJECT_LOCK_TIMEOUT=5 timeout 20 bash "$LOCK_SH" -- echo recovered 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q recovered; then ok "崩溃持有者的陈旧锁被回收"; else bad "回收 rc=$rc out=$out"; fi

# 5. 只对包装进程 kill -TERM：信号转给子进程；子进程收尾期间锁仍被占着，子进程退出后才释放；退出码是子进程的
bash "$LOCK_SH" -- bash -c 'trap "sleep 2; exit 3" TERM; while :; do sleep 0.2; done' >/dev/null 2>&1 & holder=$!
sleep 1
kill -TERM $holder
sleep 0.5
if flock -n "$BE_PROJECT_LOCK" true; then bad "包装进程收到 TERM 后、子进程还在收尾时锁就被释放了"; else ok "子进程收尾期间锁仍被占着"; fi
wait $holder; rc=$?
if [ $rc -eq 3 ]; then ok "TERM 转发给子进程，退出码是子进程的（3）"; else bad "TERM 后 rc=$rc（应为子进程的 3）"; fi
if flock -n "$BE_PROJECT_LOCK" true; then ok "子进程退出后锁可再获取"; else bad "子进程退出后锁仍被占着"; fi

# 6. 子进程被信号杀死：退出码 128+信号；INT / HUP 同样转发（非交互 shell 的后台子进程默认忽略 INT，也要能停）
for sig in TERM INT HUP; do
  # 前台调用时 INT 是默认处理；用 & 起的后台进程在非交互 shell 里会忽略 INT，所以显式恢复（模拟终端里直接运行）
  env --default-signal=INT bash "$LOCK_SH" -- sleep 30 >/dev/null 2>&1 & holder=$!
  sleep 0.5
  kill -$sig $holder
  timeout 10 tail --pid=$holder -f /dev/null; wait $holder; rc=$?
  want=$((128 + $(kill -l $sig)))
  if [ $rc -eq $want ]; then ok "$sig 转发，子进程被杀时退出码 $want"; else bad "$sig 后 rc=$rc（应为 $want）"; fi
  kids="$(pgrep -P $holder 2>/dev/null)"; kill -9 $holder $kids 2>/dev/null; wait $holder 2>/dev/null
done

# 7. 普通退出码与标准输入原样透传（交互式命令仍能读终端/管道）
bash "$LOCK_SH" -- bash -c 'exit 5' >/dev/null 2>&1; rc=$?
if [ $rc -eq 5 ]; then ok "退出码透传（5）"; else bad "退出码 rc=$rc（应为 5）"; fi
out="$(bash "$LOCK_SH" -- bash -c 'echo to-stderr >&2' 2>&1 >/dev/null)"
if echo "$out" | grep -q to-stderr; then ok "子进程的标准错误原样透传"; else bad "子进程的标准错误丢了：'$out'"; fi
out="$(echo piped | bash "$LOCK_SH" -- cat 2>/dev/null)"
if [ "$out" = piped ]; then ok "标准输入透传给子进程"; else bad "标准输入没透传：'$out'"; fi

out="$(bash "$LOCK_SH" -- echo ran <&- 2>/dev/null)"; rc=$?
if [ $rc -eq 0 ] && [ "$out" = ran ]; then ok "标准输入已关闭时照样执行"; else bad "关闭标准输入 rc=$rc out='$out'"; fi

[ $fail -eq 0 ] && echo "PASS" || { echo "FAILED" >&2; exit 1; }
