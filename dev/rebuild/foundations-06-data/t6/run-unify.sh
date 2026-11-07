#!/bin/bash
# T6: every component on be-sdk-go alpha.119 (sdk-unify.py), output in unify.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/unify.pid
python3 $R/dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.119 \
  --line "be-sdk-go alpha.119（全系统同一个 SDK 版本；订阅最后一次投递处理之前先提交死信，进程中途退出时消息不再无声消失，P6.20）" \
  --notes "换到 be-sdk-go alpha.119（全系统同一个版本）：订阅在最后一次投递处理之前先提交死信，处理成功或已应用时在同一事务删掉，失败时改成这次的错误；进程在最后一次处理中途退出时，消息留在死信里，不再无声消失（P6.20）。" \
  --subject "be-sdk-go alpha.119 (one version across the system), release {version}" ${FROM:+--from $FROM} >> $O/unify.log 2>&1
