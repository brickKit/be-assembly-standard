#!/usr/bin/env bash
# 灌本地开发/测试用的种子数据（见同目录 README.md）。⚠️ 只给本地用，
# 不出现在任何部署/CI 流程里。全程幂等：固定 idempotency_key +
# ON CONFLICT，重复跑不会重复建数据。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_OFF=$'\033[0m'
ok()   { echo "${C_GRN}✓${C_OFF} $*"; }
warn() { echo "${C_YLW}⚠${C_OFF} $*"; }
die()  { echo "${C_RED}✗${C_OFF} $*" >&2; exit 1; }

CASDOOR_URL="http://localhost:8000"
IAM_URL="http://localhost:8200"
CRM_REST="http://localhost:8102"

SEED_USER="dev.superuser"
SEED_PASSWORD="DevSeed123!"
SEED_APP="local-dev-seed-app"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }
need curl; need python3; need docker

psqlx() { docker exec -i be-postgres psql -U postgres -d brickkit_db -v ON_ERROR_STOP=1 "$@"; }
# idfor <schema> <idempotency_key>：反查某个组件自己的 command_idempotency
# 表，拿它 claim-first 幂等落下的真实行 id——组件自己的 seed 脚本（见
# ④）只负责把数据灌进去，不负责把 id 打印成本脚本能解析的格式，两边
# 用同一张幂等表当"交接协议"，不需要额外约定输出格式。
idfor() { psqlx -tA -q -c "SET search_path TO $1; SELECT result_id FROM command_idempotency WHERE idempotency_key = '$2';"; }

echo "── 检查依赖组件是否在跑 ──"
curl -sf -o /dev/null "$CASDOOR_URL/api/health" || die "Casdoor（$CASDOOR_URL）连不上，先 brickkit up"
curl -sf -o /dev/null "$IAM_URL/.well-known/jwks.json" || warn "infra-iam-casdoor（$IAM_URL）探测不到 jwks，继续尝试"
curl -sf -o /dev/null "$CRM_REST/healthz" || die "crm-opportunity（$CRM_REST）连不上，先 brickkit up"
ok "关键组件可达"

echo "── ① infra-iam-casdoor：调它自己的 make seed（建测试用户 + ROPC 测试应用）──"
# 身份数据的内容归 infra-iam-casdoor 自己的 scripts/seed.sh 所有（总纲
# SOP-W-7）——本脚本不再重复实现"怎么建 Casdoor 用户/应用"，单独
# `make -C components/infra/iam-casdoor seed` 也能独立跑通。这里还是
# 要重新查一遍 CLIENT_ID/CLIENT_SECRET/SEED_SUB——那边的 make seed 不
# 经过本脚本的变量作用域，两次查询用的是同一个只读、幂等的 Casdoor
# API，重复查不产生副作用。
( cd "$ROOT/components/infra/iam-casdoor" && make seed )

curl -c "$COOKIE_JAR" -s -o /dev/null -X POST "$CASDOOR_URL/api/login" \
  -H "Content-Type: application/json" \
  -d '{"application":"app-built-in","organization":"built-in","username":"admin","password":"123","autoSignin":true,"type":"login"}'
APP_JSON="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-application?id=admin/$SEED_APP")"
CLIENT_ID="$(echo "$APP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["clientId"])')"
CLIENT_SECRET="$(echo "$APP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["clientSecret"])')"
USER_JSON="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-user?id=brickkit/$SEED_USER")"
SEED_SUB="$(echo "$USER_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')"
[ -n "$SEED_SUB" ] || die "拿不到 $SEED_USER 的 sub"

echo "── ② infra-authz：调它自己的 make seed（建角色 + 灌全部权限键 + 授予测试用户）──"
# 授权数据的内容归 infra-authz 自己的 scripts/seed.sh 所有（同上）——它
# 自己会独立向 Casdoor 查一遍 sub，不吃本脚本的变量。
( cd "$ROOT/components/infra/authz" && make seed )

# infra-authz 的 bundle 是各组件每 ~15s 轮询一次拉进内存的（README「自我
# 鉴权」一节），刚写完 SQL 立刻拿 JWT 去调 crm-opportunity 有真实的竞态
# 窗口——bundle 还没刷新会看到"有身份、无权限"的 403，不是真的坏了。
echo "   等 18 秒，让 crm-opportunity 的权限 bundle 轮询到最新授权……"
sleep 18

echo "── ③ 换一个真实 JWT，供后面调 crm-opportunity 真实 REST 接口用 ──"
ID_TOKEN="$(curl -s -X POST "$CASDOOR_URL/api/login/oauth/access_token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "username=$SEED_USER" \
  --data-urlencode "password=$SEED_PASSWORD" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "scope=openid profile email" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id_token"])')"
[ -n "$ID_TOKEN" ] || die "拿不到 Casdoor id_token"

ACCESS_TOKEN="$(curl -s -X POST "$IAM_URL/api/iam/token" \
  -H "Content-Type: application/json" \
  -d "{\"casdoor_id_token\": \"$ID_TOKEN\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
[ -n "$ACCESS_TOKEN" ] || die "换应用 JWT 失败"
ok "已换到真实应用 JWT"

echo "── ④ mdm-customer / mdm-product：调各自组件自己的 make seed ──"
# 客户/产品数据的内容与幂等键归各组件自己的 scripts/seed.sh 所有（总纲
# SOP-W-7）——本脚本不再重复实现"怎么建一个客户/产品"，只负责编排顺序 +
# 反查 idfor 拿到本次要用的 id。单独 `make -C components/mdm/customer
# seed` 也能独立跑通，不依赖这个编排脚本。
( cd "$ROOT/components/mdm/customer" && make seed )
( cd "$ROOT/components/mdm/product" && make seed )

CUST1="$(idfor mdm_customer seed-customer-1)"
CUST2="$(idfor mdm_customer seed-customer-2)"
CUST3="$(idfor mdm_customer seed-customer-3)"
CUST4="$(idfor mdm_customer seed-customer-4)"
PROD1="$(idfor mdm_product seed-product-1)"
PROD2="$(idfor mdm_product seed-product-2)"
PROD3="$(idfor mdm_product seed-product-3)"
PROD4="$(idfor mdm_product seed-product-4)"
ok "客户：$CUST1 $CUST2 $CUST3 $CUST4（+ 1 个 DISABLED 样例，见各自组件的 seed 输出）"
ok "产品：$PROD1 $PROD2 $PROD3 $PROD4（+ 1 个 DISABLED 样例，见各自组件的 seed 输出）"

echo "── ⑤ erp-inventory：给每个示例产品灌库存（直接写库，同 Receive 的落库形状）──"
{
  echo "SET search_path TO erp_inventory;"
  for p in "$PROD1" "$PROD2" "$PROD3" "$PROD4"; do
    echo "INSERT INTO inventory_balances (product_id, warehouse_id, on_hand_qty) VALUES ('$p', '1', 200) ON CONFLICT (product_id, warehouse_id) DO UPDATE SET on_hand_qty = GREATEST(inventory_balances.on_hand_qty, 200);"
  done
} | psqlx -q
ok "已给 4 个 ACTIVE 示例产品各灌 200 件库存（DISABLED 样例不进货，符合业务语义）"

echo "── ⑥ crm-opportunity：真实调 REST 接口建示例商机（3 OPEN + 1 WON + 1 LOST）──"
mkopportunity() {
  local key="$1" name="$2" cust="$3" prod="$4" amount="$5"
  curl -s -X POST "$CRM_REST/crm/opportunity/opportunities" \
    -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
    -d "{\"idempotency_key\":\"$key\",\"name\":\"$name\",\"customer_id\":\"$cust\",\"items\":[{\"product_id\":\"$prod\",\"qty\":\"10\",\"quoted_unit_price\":\"100.00\"}],\"expected_amount\":\"$amount\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
}
stage_opportunity() {
  local id="$1" key="$2" stage="$3"
  curl -s -X POST "$CRM_REST/crm/opportunity/opportunities/$id/stage" \
    -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
    -d "{\"idempotency_key\":\"$key\",\"to_stage_id\":\"$stage\"}" >/dev/null
}

OPP1="$(mkopportunity seed-opp-1 "「本地测试」华南电子·Q1 采购意向" "$CUST1" "$PROD1" "5000.00")"
OPP2="$(mkopportunity seed-opp-2 "「本地测试」京城机械·设备更新项目" "$CUST2" "$PROD2" "12000.00")"
stage_opportunity "$OPP2" seed-opp-2-stage 3
OPP3="$(mkopportunity seed-opp-3 "「本地测试」江南纺织·年度框架合同" "$CUST3" "$PROD3" "35000.00")"
stage_opportunity "$OPP3" seed-opp-3-stage 4
OPP4="$(mkopportunity seed-opp-4 "「本地测试」西部矿业·已成交项目" "$CUST4" "$PROD4" "88000.00")"
curl -s -X POST "$CRM_REST/crm/opportunity/opportunities/$OPP4/win" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"idempotency_key":"seed-opp-4-win"}' >/dev/null
# ⚠️ 第 5 个客户/产品在各自组件的 seed 里是 DISABLED 样例（覆盖状态
# 完整度用的），CreateOpportunity 会拒绝非 ACTIVE 的客户/产品
# （service.go 真实校验），所以这里改回用 CUST1/PROD2——纯粹是拿一对
# 已知有效的组合，跟这条商机本身讲的是哪家客户没有关系。
OPP5="$(mkopportunity seed-opp-5 "「本地测试」滨海物流·已流失项目" "$CUST1" "$PROD2" "15000.00")"
curl -s -X POST "$CRM_REST/crm/opportunity/opportunities/$OPP5/lose" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"idempotency_key":"seed-opp-5-lose","reason":"「本地测试」价格谈不拢"}' >/dev/null
ok "商机：$OPP1(OPEN) $OPP2(PROPOSAL) $OPP3(NEGOTIATION) $OPP4(WON→已自动转订单) $OPP5(LOST)"

echo ""
ok "种子数据灌完了。登录方式：Casdoor 用户名 $SEED_USER / 密码 $SEED_PASSWORD"
echo "   （$OPP4 赢单后 erp-sales 会真的自动建一张订单——去 erp_sales.sales_orders 表或前端订单列表看得到）"
