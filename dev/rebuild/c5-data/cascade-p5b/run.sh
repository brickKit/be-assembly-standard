#!/bin/bash
# C5 P5: the components pinning erp/costing move to 3.0.1 (an unfilled gap keeps the time its wait began), and
# theirs. Output in run.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c5-data/cascade-p5b
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run -q --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.121 --moved erp/costing \
  --line '{version}：依赖换到 erp/costing 3.0.1（一致性考试后的修正，装配项目阶段计划 C5 的 P5）及随之连锁的版本；行为不变。' \
  --notes '依赖换到 erp/costing 3.0.1 及随之连锁的版本；本组件行为不变。' \
  --subject '{version}: erp/costing 3.0.1 and what moved with it (C5 P5)'
