#!/bin/bash
# C7 P7: every Go component on be-sdk-go alpha.126 (the consistency exam's kernel fixes), then the tools and the shells.
# Output in run.log; "P7SDK ALL-DONE" or "P7SDK FAILED <what>".
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c7-data/p7-sdk126
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.126 --logs $O/logs \
  --line '{version}：be-sdk-go alpha.126（全系统同一个 SDK 版本；流程内核在员工投影变化后立即重新解析暂停的任务，没有员工目录时岗位任务答 NOT_QUALIFIED，装配项目阶段计划 C7 的 P7）及随之连锁的版本；本组件行为不变。' \
  --notes 'be-sdk-go alpha.126（全系统同一个 SDK 版本；流程内核的两处修正）及随之连锁的版本；本组件行为不变。' \
  --subject '{version}: be-sdk-go alpha.126 (C7 P7)' || { echo "P7SDK FAILED unify"; exit 1; }
bash $O/tools.sh; tail -1 $O/run.out
grep -q "TOOLS ALL-DONE" $O/run.out || { echo "P7SDK FAILED tools"; exit 1; }
bash $O/shells.sh > $O/shells.log 2>&1; tail -1 $O/shells.log
grep -q "SHELLS ALL-DONE" $O/shells.log || { echo "P7SDK FAILED shells"; exit 1; }
echo "P7SDK ALL-DONE"
