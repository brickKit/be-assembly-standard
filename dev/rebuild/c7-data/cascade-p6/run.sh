#!/bin/bash
# C7 P6: erp/purchase 3.0.9 moves erp/finance (its pin) and erp/payment (finance's pin), then be/go-core. Output in run.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c7-data/cascade-p6
echo $$ > $O/pid
cd $R && PYTHONDONTWRITEBYTECODE=1 uv run --with pyyaml python3 dev/rebuild/experiment-scripts/sdk-unify.py \
  --sdk v3.0.0-alpha.125 --moved erp/purchase --moved mdm/employee --moved infra/workflow --logs $O/logs \
  --line '{version}：依赖换到 erp/purchase 3.0.9、mdm/employee 3.0.7（审批人的种子，装配项目阶段计划 C7 的 P6）及随之连锁的版本；本组件行为不变。' \
  --notes '依赖换到 erp/purchase 3.0.9、mdm/employee 3.0.7（审批人的种子）及随之连锁的版本；本组件行为不变。' \
  --subject '{version}: erp/purchase 3.0.9 and what moved with it (C7 P6)' || { echo "CASCADEP6 FAILED unify"; exit 1; }
sed -e 's/shells-p6/shells/g; s/release-p6-/release-/g; s/for shell in go-infra go-core/for shell in go-core/' $R/dev/rebuild/c7-data/shells-p6.sh > $O/shells.sh
bash $O/shells.sh > $O/shells.log 2>&1; tail -1 $O/shells.log
grep -q "SHELLS ALL-DONE" $O/shells.log && echo "CASCADEP6 ALL-DONE" || echo "CASCADEP6 FAILED shells"
