#!/bin/bash
# C7 P4: every Go component on be-sdk-go 3.0.0-alpha.125 (the kernel's additions for the approvals); erp/purchase 3.0.7
# and erp/payment 3.0.11 are on it already and move again for their pins. Output in run.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c7-data/unify-p4
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.125 --logs $O/logs \
  --line '{version}：be-sdk-go alpha.125（全系统同一个 SDK 版本；流程内核为采购与收付款的审批补的几样，装配项目阶段计划 C7 的 P4）及随之连锁的版本；本组件行为不变。' \
  --notes 'be-sdk-go alpha.125（全系统同一个 SDK 版本；流程内核为审批迁移补的几样）及随之连锁的版本；本组件行为不变。' \
  --subject '{version}: be-sdk-go alpha.125 (C7 P4)'
echo "UNIFYP4 EXIT rc=$?"
