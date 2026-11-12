#!/bin/bash
# C7 P3: every Go component on be-sdk-go 3.0.0-alpha.122 (the flow kernel). Output in run.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c7-data/unify-p3
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.122 \
  --line '{version}：be-sdk-go alpha.122（全系统同一个 SDK 版本；SDK 加了流程内核，线协议第 17 章，装配项目阶段计划 C7 的 P3）；行为不变。' \
  --notes 'be-sdk-go alpha.122（全系统同一个 SDK 版本；SDK 加了流程内核）；本组件行为不变。' \
  --subject '{version}: be-sdk-go alpha.122 (C7 P3)'
