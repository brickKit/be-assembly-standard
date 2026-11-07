#!/bin/bash
# T10e step 1: every component on be-sdk-go alpha.115 (sdk-unify.py), output in unify.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/unify.pid
python3 $R/dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.115 \
  --line "be-sdk-go alpha.115（全系统同一个 SDK 版本；冷热数据：多层子表、叶子表的多列主键、text[]、部署时给保留期与选路线、标准管理路由、写屏障固定 search_path）" \
  --notes "换到 be-sdk-go alpha.115（全系统同一个版本）：SDK 补了多层子表、叶子表的多列主键、text[]、部署时给保留期与选路线、冷热数据的标准管理路由、写屏障固定 search_path；没有声明数据类别的组件行为不变。" \
  --subject "be-sdk-go alpha.115 (one version across the system), release {version}" ${FROM:+--from $FROM} >> $O/unify.log 2>&1
