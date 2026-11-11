#!/bin/bash
# C5 P5: the components pinning erp/purchase move to 3.0.4 (it asks erp/costing before a return). Output in run.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c5-data/cascade-p5
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.121 --moved erp/purchase \
  --line '{version}：依赖换到 erp/purchase 3.0.4（退货前问 erp/costing 的可退数量，装配项目阶段计划 C5 的 P5）及随之连锁的版本；行为不变。' \
  --notes '依赖换到 erp/purchase 3.0.4（退货前问成本组件的可退数量）及随之连锁的版本；本组件行为不变。' \
  --subject '{version}: erp/purchase 3.0.4 and what moved with it (C5 P5)'
