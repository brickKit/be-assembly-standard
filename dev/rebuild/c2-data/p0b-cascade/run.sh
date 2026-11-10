#!/usr/bin/env bash
# C2 P0b: the components depending on mdm/partner 3.0.39 (the supplier role) and erp/inventory 3.0.37 (purchase
# receipts and returns) move for their pins: version up, every test, release.
cd "$(dirname "$0")/../../../.." || exit 1
O=dev/rebuild/c2-data/p0b-cascade
echo $$ > $O/run.pid
export PYTHONDONTWRITEBYTECODE=1
python3 dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.121 --moved mdm/partner --moved erp/inventory \
  --logs $O/logs \
  --line "依赖换到 mdm/partner 3.0.39（供应商角色）与 erp/inventory 3.0.37（采购收货与退货；装配项目阶段计划 C2 的 P0b），行为不变" \
  --notes "依赖换到 mdm/partner 3.0.39 与 erp/inventory 3.0.37（采购要的能力），行为不变。" \
  --subject "{version}: dependencies on mdm/partner 3.0.39 and erp/inventory 3.0.37; behaviour unchanged"
echo "CASCADE RUN-END $?"
