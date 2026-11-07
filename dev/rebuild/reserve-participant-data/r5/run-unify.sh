#!/bin/bash
# R5: every component on be-sdk-go alpha.117 (sdk-unify.py), output in unify.log; the component logs in logs/.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/unify.pid
python3 $R/dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.117 --logs $O/logs \
  --line "be-sdk-go alpha.117（全系统同一个 SDK 版本；SDK 加了预占的参与方 \`reserve\`，线协议第 16 章）" \
  --notes "换到 be-sdk-go alpha.117（全系统同一个版本）：SDK 加了预占的参与方 \`reserve\`（线协议第 16 章），迁移 \`0024_reserve\` 在每个组件的 schema 里建两张表；不做参与方的组件行为不变。" \
  --subject "be-sdk-go alpha.117 (one version across the system), release {version}" ${FROM:+--from $FROM} >> $O/unify.log 2>&1
