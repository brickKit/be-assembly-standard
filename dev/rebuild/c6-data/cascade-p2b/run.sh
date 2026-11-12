#!/bin/bash
# C6 P2b: the components pinning erp/sales move to 3.0.50 (crm/opportunity's quote requests). Output in run.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c6-data/cascade-p2b
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.121 --moved erp/sales \
  --line '{version}：依赖换到 erp/sales 3.0.50（商机的请求报价，装配项目阶段计划 C6 的 P2b）及随之连锁的版本；行为不变。' \
  --notes '依赖换到 erp/sales 3.0.50（商机的请求报价）及随之连锁的版本；本组件行为不变。' \
  --subject '{version}: erp/sales 3.0.50 and what moved with it (C6 P2b)'
