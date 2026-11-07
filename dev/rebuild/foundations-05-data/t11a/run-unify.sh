#!/bin/bash
# T12: every component on be-sdk-go alpha.116 (sdk-unify.py), output in unify.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/unify.pid
python3 $R/dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.116 \
  --line "be-sdk-go alpha.116（全系统同一个 SDK 版本；冷热数据：每天的孤儿清理、擦除作废导出、已销毁的记录从决定起答不存在、释放在事务之外读备份记录）" \
  --notes "换到 be-sdk-go alpha.116（全系统同一个版本）：SDK 加了每天的孤儿清理作业，擦除作废同一类别的导出，已销毁的记录从销毁决定起按身份读答不存在，释放在事务之外读备份记录；没有声明数据类别的组件行为不变。" \
  --subject "be-sdk-go alpha.116 (one version across the system), release {version}" ${FROM:+--from $FROM} >> $O/unify.log 2>&1
