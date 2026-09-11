#!/usr/bin/env bash
# 灌本地开发/测试用的种子数据（见同目录 README.md）。⚠️ 只给本地用，
# 不出现在任何部署/CI 流程里。全程幂等：固定 idempotency_key +
# ON CONFLICT，重复跑不会重复建数据。
#
# ⚠️ 本脚本现在是一个薄编排（总纲 SOP-W-7）：数据本身的内容全部归各
# 组件自己的 scripts/seed.sh 所有，这里只负责两件事——① 按依赖顺序
# 调用各组件的 make seed；② 补 erp-inventory 这一步真正跨组件、没有
# 自然归属的部分（product_id 是 erp-inventory 的不透明外键，本组件
# 明确不依赖 mdm-product，给 mdm-product 的真实产品灌库存这件事只能
# 留在编排层）。
#
# ⚠️ 顺序不能乱：erp-inventory 的库存必须先于 crm-opportunity 建好——
# crm-opportunity 自己的 make seed 会建一条 WON 商机，真实触发 erp-sales
# 自动建单确认（含 Reserve 库存），库存不够会走 TCC 补偿建异常待办，
# 不是失败，但不是我们想要的"打开就是一条干净确认好的订单"这个演示
# 效果。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

C_GRN=$'\033[32m'; C_OFF=$'\033[0m'
ok()  { echo "${C_GRN}✓${C_OFF} $*"; }
die() { echo -e "\033[31m✗\033[0m $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }
need curl; need docker

psqlx() { docker exec -i be-postgres psql -U postgres -d brickkit_db -v ON_ERROR_STOP=1 "$@"; }
# idfor <schema> <idempotency_key>：反查某个组件自己的 command_idempotency
# 表，拿它 claim-first 幂等落下的真实行 id——组件自己的 seed 脚本只负责
# 把数据灌进去，不负责把 id 打印成本脚本能解析的格式，两边用同一张幂等
# 表当"交接协议"（总纲 SOP-W-7）。
idfor() { psqlx -tA -q -c "SET search_path TO $1; SELECT result_id FROM command_idempotency WHERE idempotency_key = '$2';"; }

echo "── 检查依赖组件是否在跑 ──"
curl -sf -o /dev/null "http://localhost:8102/healthz" || die "crm-opportunity（:8102）连不上，先 brickkit up"
ok "关键组件可达"

echo "── ① mdm-customer / mdm-product：调各自组件自己的 make seed ──"
( cd "$ROOT/components/mdm/customer" && make seed )
( cd "$ROOT/components/mdm/product" && make seed )

echo "── ② erp-inventory：给每个示例产品灌库存（直接写库，同 Receive 的落库形状）──"
# ⚠️ product_id 对 erp-inventory 是不透明外键（本组件明确不依赖
# mdm-product），这一步天然没有单一归属，留在编排层——同"顺序"这件事
# 本身一样，是装配层该管的事，不是哪个组件该管的事。
PROD1="$(idfor mdm_product seed-product-1)"
PROD2="$(idfor mdm_product seed-product-2)"
PROD3="$(idfor mdm_product seed-product-3)"
PROD4="$(idfor mdm_product seed-product-4)"
{
  echo "SET search_path TO erp_inventory;"
  for p in "$PROD1" "$PROD2" "$PROD3" "$PROD4"; do
    echo "INSERT INTO inventory_balances (product_id, warehouse_id, on_hand_qty) VALUES ('$p', '1', 200) ON CONFLICT (product_id, warehouse_id) DO UPDATE SET on_hand_qty = GREATEST(inventory_balances.on_hand_qty, 200);"
  done
} | psqlx -q
ok "已给 4 个 ACTIVE 示例产品各灌 200 件库存（DISABLED 样例不进货，符合业务语义）"

echo "── ③ crm-opportunity：调它自己的 make seed（链式建好身份/授权/客户/产品/商机）──"
# 身份（infra-iam-casdoor）/授权（infra-authz）/客户/产品四个前置步骤
# 已经在 crm-opportunity 自己的 Makefile 里链式调用过一遍——这里再调
# 用一次是幂等的重复确认，不是浪费（同强依赖链式调用的既有判据：单独
# make -C components/crm/opportunity seed 也要能跑通完整数据）。
( cd "$ROOT/components/crm/opportunity" && make seed )

echo ""
ok "种子数据灌完了。登录方式：Casdoor 用户名 dev.superuser / 密码 DevSeed123!"
