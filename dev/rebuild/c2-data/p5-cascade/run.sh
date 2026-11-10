#!/usr/bin/env bash
# C2 P5: the components depending on mdm/product 3.0.38 (four services purchasable in its seed, for the purchase
# seed's acceptances) move for their pins: version up, every test, release. erp/purchase is released after them by
# hand (3.0.1 has changes of its own): it is passed as moved so that the run leaves it alone.
cd "$(dirname "$0")/../../../.." || exit 1
O=dev/rebuild/c2-data/p5-cascade
echo $$ > $O/run.pid
export PYTHONDONTWRITEBYTECODE=1
source dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
python3 dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.121 --moved mdm/product --moved erp/purchase \
  --logs $O/logs \
  --line "依赖换到 mdm/product 3.0.38（种子让四个服务可采购；装配项目阶段计划 C2 的 P5），行为不变" \
  --notes "依赖换到 mdm/product 3.0.38（种子让四个服务可采购），行为不变。" \
  --subject "{version}: dependency on mdm/product 3.0.38; behaviour unchanged"
echo "CASCADE RUN-END $?"
