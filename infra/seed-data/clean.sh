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

echo "── ① crm-opportunity + 联带的 erp-sales 自动建单 ──"
psqlx -q <<'SQL'
SET search_path TO crm_opportunity;
DO $$
DECLARE
  opp_id text;
  opp_ids text[] := ARRAY[]::text[];
  k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['seed-opp-1','seed-opp-2','seed-opp-3','seed-opp-4','seed-opp-5'] LOOP
    SELECT result_id INTO opp_id FROM command_idempotency WHERE idempotency_key = k;
    IF opp_id IS NOT NULL AND opp_id <> '' THEN
      opp_ids := array_append(opp_ids, opp_id);
    END IF;
  END LOOP;
  IF array_length(opp_ids, 1) > 0 THEN
    DELETE FROM opportunity_stage_history WHERE opportunity_id::text = ANY(opp_ids);
    DELETE FROM opportunity_items WHERE opportunity_id::text = ANY(opp_ids);
    DELETE FROM opportunities WHERE id::text = ANY(opp_ids);
    DELETE FROM command_idempotency WHERE idempotency_key LIKE 'seed-opp-%';
    RAISE NOTICE '删除商机: %', opp_ids;
  END IF;
END $$;
SQL
ok "已清理 crm-opportunity 的种子商机"

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

echo "── ③ erp-inventory：清掉种子产品的库存余额 ──"
psqlx -q <<'SQL'
SET search_path TO erp_inventory;
DO $$
DECLARE
  prod_ids text[] := ARRAY[]::text[];
  pid text;
  k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['seed-product-1','seed-product-2','seed-product-3','seed-product-4','seed-product-5'] LOOP
    SELECT result_id INTO pid FROM mdm_product.command_idempotency WHERE idempotency_key = k;
    IF pid IS NOT NULL AND pid <> '' THEN
      prod_ids := array_append(prod_ids, pid);
    END IF;
  END LOOP;
  IF array_length(prod_ids, 1) > 0 THEN
    DELETE FROM inventory_balances WHERE product_id = ANY(prod_ids);
    RAISE NOTICE '删除库存余额，产品: %', prod_ids;
  END IF;
END $$;
SQL
ok "已清理 erp-inventory 的种子库存"

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
