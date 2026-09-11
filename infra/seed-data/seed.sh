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
SEED_ROLE="dev_superuser"
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

echo "── ① Casdoor：登录 admin、建测试用户、建 ROPC 测试应用 ──"
curl -c "$COOKIE_JAR" -s -o /dev/null -X POST "$CASDOOR_URL/api/login" \
  -H "Content-Type: application/json" \
  -d '{"application":"app-built-in","organization":"built-in","username":"admin","password":"123","autoSignin":true,"type":"login"}'

# add-user 对已存在的用户会报错但不影响后续——用 get-user 先判断存在与否，
# 幂等地跳过创建（不能靠 add-user 的返回码，Casdoor 对"已存在"和"真的
# 失败"用同一种 HTTP 200 + status:error 形状回，靠 msg 文本分辨不可靠）。
EXISTING_USER="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-user?id=brickkit/$SEED_USER" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("yes" if d.get("data") else "no")')"
if [ "$EXISTING_USER" = "no" ]; then
  curl -b "$COOKIE_JAR" -s -X POST "$CASDOOR_URL/api/add-user" \
    -H "Content-Type: application/json" \
    -d "{\"owner\":\"brickkit\",\"name\":\"$SEED_USER\",\"password\":\"$SEED_PASSWORD\",\"email\":\"$SEED_USER@example.com\",\"displayName\":\"「本地测试」超级测试用户\",\"type\":\"normal-user\",\"isAdmin\":false,\"countryCode\":\"CN\"}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("status")=="ok", d' \
    || die "创建 Casdoor 用户失败"
  ok "已创建 Casdoor 用户 $SEED_USER"
else
  ok "Casdoor 用户 $SEED_USER 已存在，跳过创建"
fi

EXISTING_APP="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-application?id=admin/$SEED_APP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("yes" if d.get("data") else "no")')"
if [ "$EXISTING_APP" = "no" ]; then
  curl -b "$COOKIE_JAR" -s -X POST "$CASDOOR_URL/api/add-application" \
    -H "Content-Type: application/json" \
    -d "{\"owner\":\"admin\",\"name\":\"$SEED_APP\",\"displayName\":\"$SEED_APP\",\"organization\":\"brickkit\",\"cert\":\"cert-built-in\",\"enablePassword\":true,\"enableSignUp\":false,\"redirectUris\":[\"http://localhost:3000/callback\"],\"grantTypes\":[\"authorization_code\",\"password\",\"refresh_token\"],\"tokenFormat\":\"JWT\",\"expireInHours\":24,\"refreshExpireInHours\":168}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("status")=="ok", d' \
    || die "创建 Casdoor ROPC 测试应用失败"
  ok "已创建 Casdoor ROPC 测试应用 $SEED_APP（⚠️ 只应该存在于本地环境，见 README）"
else
  ok "Casdoor ROPC 测试应用 $SEED_APP 已存在，跳过创建"
fi

APP_JSON="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-application?id=admin/$SEED_APP")"
CLIENT_ID="$(echo "$APP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["clientId"])')"
CLIENT_SECRET="$(echo "$APP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["clientSecret"])')"

USER_JSON="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-user?id=brickkit/$SEED_USER")"
SEED_SUB="$(echo "$USER_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')"
[ -n "$SEED_SUB" ] || die "拿不到 $SEED_USER 的 sub"
ok "$SEED_USER 的 sub = $SEED_SUB"

echo "── ② infra-authz：直接建角色 + 灌全部权限键 + 授予测试用户 ──"
# ⚠️ 这批全是灌进真实共享数据库的假数据（用户已明确同意），role_permissions
# 按 registry/permissions.tsv 现读现灌，不依赖 permissions 表里可能混着的
# 其它测试残留数据。
PERM_KEYS="$(python3 -c "
import csv
with open('registry/permissions.tsv') as f:
    rows = [r for r in csv.DictReader(f, delimiter='\t') if not r['deprecated'].strip()]
for r in rows:
    print(r['key'])
")"

{
  echo "SET search_path TO infra_authz;"
  echo "INSERT INTO roles (code, name, is_system) VALUES ('$SEED_ROLE', '「本地测试」超级测试角色', false) ON CONFLICT (code) DO NOTHING;"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    echo "INSERT INTO role_permissions (role_code, permission_key) VALUES ('$SEED_ROLE', '$key') ON CONFLICT DO NOTHING;"
  done <<< "$PERM_KEYS"
  echo "INSERT INTO user_roles (sub, role_code) VALUES ('$SEED_SUB', '$SEED_ROLE') ON CONFLICT DO NOTHING;"
} | psqlx -q
ok "已授予 $SEED_USER 角色 $SEED_ROLE（$(echo "$PERM_KEYS" | grep -c .) 个权限键）"

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
