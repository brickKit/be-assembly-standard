#!/usr/bin/env bash
# C2 P4: the components depending on mdm/partner 3.0.40 (the seed's supplier roles) and infra/iam-casdoor 3.0.44 (two
# purchase accounts) move for their pins: version up, every test, release. erp/purchase is not released yet and
# already pins mdm/partner 3.0.40: it is passed as moved so that the run leaves it alone.
cd "$(dirname "$0")/../../../.." || exit 1
O=dev/rebuild/c2-data/p4-cascade
echo $$ > $O/run.pid
export PYTHONDONTWRITEBYTECODE=1
source dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
python3 dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.121 --moved mdm/partner --moved infra/iam-casdoor \
  --moved erp/purchase --logs $O/logs \
  --line "依赖换到 mdm/partner 3.0.40（种子开供应商角色；装配项目阶段计划 C2 的 P4a），行为不变" \
  --notes "依赖换到 mdm/partner 3.0.40（种子开供应商角色），行为不变。" \
  --subject "{version}: dependency on mdm/partner 3.0.40; behaviour unchanged"
echo "CASCADE RUN-END $?"
