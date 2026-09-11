#!/usr/bin/env bash
# 灌本地开发/测试用的种子数据（见同目录 README.md）。⚠️ 只给本地用，
# 不出现在任何部署/CI 流程里。全程幂等：固定 idempotency_key +
# ON CONFLICT，重复跑不会重复建数据。
#
# ⚠️ 本脚本现在是一个薄编排（总纲 SOP-W-7）：数据本身的内容全部归各
# 组件自己的 scripts/seed.sh 所有，这里只负责一件事——按依赖顺序调用
# 各组件的 make seed。原来留在这里的"给 mdm-product 的真实产品灌库存"
# 那一步已经挪回 erp-inventory 自己的 make seed（它自己反查
# mdm-product 的种子数据探测式关联，见该组件的 scripts/seed.sh），本
# 脚本不再需要知道任何一个组件的表结构。
#
# ⚠️ 顺序不能乱：erp-inventory 必须先于 crm-opportunity 建好——
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
need curl

echo "── 检查关键组件是否在跑 ──"
curl -sf -o /dev/null "http://localhost:8086/healthz" || die "erp-inventory（:8086）连不上，先 brickkit up"
curl -sf -o /dev/null "http://localhost:8102/healthz" || die "crm-opportunity（:8102）连不上，先 brickkit up"
ok "关键组件可达"

echo "── ① mdm-customer / mdm-product：调各自组件自己的 make seed ──"
( cd "$ROOT/components/mdm/customer" && make seed )
( cd "$ROOT/components/mdm/product" && make seed )

echo "── ② erp-inventory：调它自己的 make seed（自成一体演示数据 + 探测式给真实产品灌库存）──"
( cd "$ROOT/components/erp/inventory" && make seed )

echo "── ③ crm-opportunity：调它自己的 make seed（链式建好身份/授权/客户/产品/商机）──"
# 身份（infra-iam-casdoor）/授权（infra-authz）/客户/产品四个前置步骤
# 已经在 crm-opportunity 自己的 Makefile 里链式调用过一遍——这里再调
# 用一次是幂等的重复确认，不是浪费（同强依赖链式调用的既有判据：单独
# make -C components/crm/opportunity seed 也要能跑通完整数据）。
( cd "$ROOT/components/crm/opportunity" && make seed )

echo ""
ok "种子数据灌完了。登录方式：Casdoor 用户名 dev.superuser / 密码 DevSeed123!"
