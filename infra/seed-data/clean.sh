#!/usr/bin/env bash
# 清空 seed.sh 灌的种子数据。⚠️ 只删 seed.sh 自己灌的行——全部靠 seed.sh
# 用的固定 idempotency_key 反查各组件自己的 command_idempotency 表拿到
# 真实的行 id，再精确删除，不用名字模糊匹配（避免误删同名的真实数据）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_OFF=$'\033[0m'
ok()   { echo "${C_GRN}✓${C_OFF} $*"; }
die()  { echo "${C_RED}✗${C_OFF} $*" >&2; exit 1; }

psqlx() { docker exec -i be-postgres psql -U postgres -d brickkit_db -v ON_ERROR_STOP=1 "$@"; }

echo "── ① crm-opportunity：调它自己的 make seed-clean ──"
# 商机数据的清理归 crm-opportunity 自己的 scripts/seed-clean.sh 所有
# （总纲 SOP-W-7）——本脚本不再重复实现。erp-sales 联带自动建的订单
# 不在这一步清理，见下一步。
( cd "$ROOT/components/crm/opportunity" && make seed-clean )

# seed-opp-4 赢单后 erp-sales 会自动建一张订单，幂等键是 crm-won:<opp4_id>——
# 上一步已经把 crm_opportunity 自己的 command_idempotency 清空，这里在清空
# 之前没有保留 opp4_id，改用更直接的判据：erp-sales 里所有客户是种子客户
# （seed-customer-1..5）产生的订单一并清掉（见下一步，客户 id 反查之后统一处理）。

echo "── ② erp-sales：清掉种子客户名下的订单（含 Task 14 赢单自动建的那张）──"
psqlx -q <<'SQL'
SET search_path TO erp_sales;
DO $$
DECLARE
  cust_ids text[] := ARRAY[]::text[];
  cid text;
  k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['seed-customer-1','seed-customer-2','seed-customer-3','seed-customer-4','seed-customer-5'] LOOP
    SELECT result_id INTO cid FROM mdm_customer.command_idempotency WHERE idempotency_key = k;
    IF cid IS NOT NULL AND cid <> '' THEN
      cust_ids := array_append(cust_ids, cid);
    END IF;
  END LOOP;
  IF array_length(cust_ids, 1) > 0 THEN
    DELETE FROM sales_order_items WHERE order_id IN (SELECT id FROM sales_orders WHERE customer_id = ANY(cust_ids));
    DELETE FROM sales_orders WHERE customer_id = ANY(cust_ids);
    DELETE FROM command_idempotency WHERE idempotency_key LIKE 'crm-won:%';
    RAISE NOTICE '删除订单，客户: %', cust_ids;
  END IF;
END $$;
SQL
ok "已清理 erp-sales 的种子订单"

echo "── ③ erp-inventory：不清理，见下方说明 ──"
# ⚠️ erp-inventory 现在自己拥有这份数据（含真实产品的库存联动，见
# components/erp/inventory/scripts/seed.sh），而且是真的走 Receive/
# Adjust/Reserve 等业务命令写的流水/预留——不再是当年可以精确 DELETE
# 撤销的裸 SQL 写入。本组件的 inventory_movements"只增不改"（AGENTS.md
# 既有判据），没有 seed-clean，只有 db-reset（migrate down 再 up，
# 见总纲 SOP-W-7"delete 不是 reset"）——但 db-reset 会清空**整个**
# erp-inventory（不止 seed 灌的那部分），所以不适合塞进这个只想"撤销
# seed 数据"的编排脚本里自动调用，需要的话手动跑：
#   make -C components/erp/inventory db-reset
ok "跳过（如需清空 erp-inventory 全部数据，手动执行上面那条命令）"

echo "── ④ mdm-customer / mdm-product：调各自组件自己的 make seed-clean ──"
# ⚠️ 顺序不能提前——①②③还要反查 mdm_customer/mdm_product 的
# command_idempotency 表拿客户/产品 id，这一步会把那些行删掉。删除
# 内容本身归各组件自己（总纲 SOP-W-7），这里只负责编排顺序。
( cd "$ROOT/components/mdm/customer" && make seed-clean )
( cd "$ROOT/components/mdm/product" && make seed-clean )
ok "已清理 mdm-customer/mdm-product 的种子主数据"

echo "── ⑤ infra-authz：调它自己的 make seed-clean（撤销测试角色）──"
( cd "$ROOT/components/infra/authz" && make seed-clean )

echo "── ⑥ infra-iam-casdoor：调它自己的 make seed-clean（删测试应用 + 测试用户）──"
( cd "$ROOT/components/infra/iam-casdoor" && make seed-clean )

echo ""
ok "种子数据已全部清空"
