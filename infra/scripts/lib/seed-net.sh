#!/usr/bin/env bash
# 装配仓库的开发工具（不是组件的可移植资产——scripts/seed.sh 本来就靠
# 相对路径读 $ROOT/brickkit.yaml/registry/ports.tsv，脱离本仓库检出单独
# 跑就不成立，抽到这里跟"组件保持独立部署能力"的铁律六无关，铁律六管
# 的是业务逻辑代码）。供各组件 scripts/seed.sh 用 `source` 引入，把
# "怎么连上 brickkit 网络、怎么换一个真实 JWT"这段近乎逐字重复的样板
# 只维护一份。背景与权衡见 docs/dev/架构复盘-servedBy落地后的自有改进
# 空间.md 发现一。
#
# 用法：在算完 DIR/ROOT 之后 source 本文件——
#   DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   ROOT="$(cd "$DIR/../../.." && pwd)"
#   source "$ROOT/infra/scripts/lib/seed-net.sh"
# 本文件不自己 set -euo pipefail（沿用调用方已经设置的那份），也不算
# DIR/ROOT——它假设调用方已经算好并 export 到当前 shell。
#
# 提供的函数：
#   ok/die/need                    通用小工具
#   component_version <id>         读 brickkit.yaml 当前版本
#   service_name <id>              -> 版本化服务名（brickKit 地址转换规则）
#   seed_net_check                 -> 设 $NET，网络不存在就 die
#   with_toolbox [net]             -> 起一次性工具箱容器，设好 curl()
#                                      包装函数 + COOKIE_JAR + EXIT trap；
#                                      不传参数默认用 $NET（先调
#                                      seed_net_check 的话就已经有）
#   check_healthz <url> <label>    -> curl -sf 检查，不通就 die
#   get_app_jwt <username>         -> 换 ROPC 应用 JWT 的完整流程，回显
#                                      access token；内部按需自动跑一次
#                                      Casdoor admin 登录 + 取 ROPC 应用
#                                      client_id/secret，重复调用不会
#                                      重复登录
#   sub_of <username>              -> 查 Casdoor 内部用户 id（sub），
#                                      同样按需自动完成 admin 登录
#   wait_bundle_refresh            -> 等 18 秒权限 bundle 轮询刷新，带提示
#   psqlx                          -> docker exec 进 be-postgres 连
#                                      brickkit_db 跑 psql（会消费 stdin
#                                      的 heredoc，也接受 -c/-q 等参数）
#   idfor <schema> <key>           -> 反查另一个组件的
#                                      command_idempotency 表拿真实行 id
#
# 固定约定（全部种子脚本共享，不是这次才发明的）：ROPC 应用固定
# local-dev-seed-app，测试账号密码固定 DevSeed123!，Casdoor admin/123
# 是 be-casdoor 镜像自带的内置账号。

C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
ok()  { echo "${C_GRN}✓${C_OFF} $*"; }
die() { echo "${C_RED}✗${C_OFF} $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

# ⚠️ 真机踩到的坑（阶段四附加 Task 0.5）：brickKit 的 servedBy 合并部署
# 下，组件可能被收编进某个外壳，没有独立容器、也没有发布到宿主机的
# 端口——不能再直接从宿主机 curl/docker ps 按名字前缀找容器，必须按
# brickKit 自己给依赖方注入 *_ENDPOINT 时用的同一条地址转换规则直接拼
# 目标地址（componentId+version 转小写、"/"和"."全部替换成"-"——brickKit
# 源码 internal/manifest/servicename.go 的 ServiceName()，已向 brickKit
# 确认这条规则不区分部署形态：独立部署时它是容器自己的 compose service
# 名，servedBy 合并部署时它是外壳容器网络别名的一个别名，两种形态解析
# 到的都是正确位置，调用方不需要检测、也不需要关心究竟是哪一种）。
component_version() {
  awk -v id="$1" '$0 ~ "^  - id: "id"$"{f=1;next} f&&/^    version:/{print $2;exit}' "$ROOT/brickkit.yaml"
}
service_name() { echo "$1-$(component_version "$1")" | tr '[:upper:]' '[:lower:]' | tr '/.' '--'; }

seed_net_check() {
  NET="${BRICKKIT_NET:-brickkit-$(basename "$ROOT")-net}"
  docker network inspect "$NET" >/dev/null 2>&1 || die "docker 网络 $NET 不存在——先把本组件 brickkit up 起来（整套或只装这一个，servedBy 合并部署也可以）"
}

# ⚠️ 真机踩到的坑：--user 必须跟宿主机当前用户一致——COOKIE_JAR 是 host
# 侧 mktemp 建出来的（属主是宿主机用户，权限 0600），curlimages/curl 镜像
# 默认用镜像自带的非 root 用户跑，不加 --user 的话容器内的 curl 连自己的
# cookie jar 都没权限读写（`-c`/`-b` 全部静默失败，Casdoor 返回"Please
# login first"，症状极难看出是权限问题不是登录逻辑问题）。
with_toolbox() {
  local net="${1:-$NET}"
  TOOLBOX="seed-toolbox-$$"
  docker run -d --rm --name "$TOOLBOX" --network "$net" \
    --user "$(id -u):$(id -g)" --add-host host.docker.internal:host-gateway -v /tmp:/tmp \
    curlimages/curl:latest sleep 3600 >/dev/null
  curl() { docker exec -i "$TOOLBOX" curl "$@"; }
  COOKIE_JAR="$(mktemp)"
  trap 'rm -f "$COOKIE_JAR"; docker rm -f "$TOOLBOX" >/dev/null 2>&1' EXIT
}

check_healthz() { # url label
  curl -sf -o /dev/null "$1" || die "$2（$1）连不上，先 brickkit up"
}

CASDOOR_URL="${CASDOOR_URL:-http://host.docker.internal:8000}"
IAM_URL="${IAM_URL:-http://$(service_name infra/iam-casdoor):8200}"
SEED_PASSWORD="${SEED_PASSWORD:-DevSeed123!}"
SEED_APP="${SEED_APP:-local-dev-seed-app}"

_casdoor_admin_ready=""
_ensure_casdoor_admin() {
  [ -n "$_casdoor_admin_ready" ] && return 0
  curl -c "$COOKIE_JAR" -s -o /dev/null -X POST "$CASDOOR_URL/api/login" \
    -H "Content-Type: application/json" \
    -d '{"application":"app-built-in","organization":"built-in","username":"admin","password":"123","autoSignin":true,"type":"login"}'
  local app_json
  app_json="$(curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-application?id=admin/$SEED_APP")"
  # strict=False：Casdoor 的 get-application 响应里 signinItems 的
  # customCss 字段真实登录过一次后会带字面换行符（不是转义的 \n），严格
  # 模式的 JSON 解析会报 "Invalid control character"——只要 clientId/
  # clientSecret 两个字段，不关心这个 UI 主题字段本身对不对（踩坑记录 C19）。
  CLIENT_ID="$(echo "$app_json" | python3 -c 'import json,sys; print(json.load(sys.stdin, strict=False)["data"]["clientId"])')"
  CLIENT_SECRET="$(echo "$app_json" | python3 -c 'import json,sys; print(json.load(sys.stdin, strict=False)["data"]["clientSecret"])')"
  _casdoor_admin_ready=1
}

# get_app_jwt <username> -> access token：admin/123 登录 Casdoor → 换
# ROPC 应用 client_id/secret → 拿目标用户的 id_token → 换 infra-iam-casdoor
# 签发的应用 JWT。同一个脚本换多个身份的 JWT 只登录一次（_ensure_casdoor_admin
# 内部去重）。
get_app_jwt() {
  local username="$1" id_token access_token
  _ensure_casdoor_admin
  id_token="$(curl -s -X POST "$CASDOOR_URL/api/login/oauth/access_token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "username=$username" \
    --data-urlencode "password=$SEED_PASSWORD" \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$CLIENT_SECRET" \
    --data-urlencode "scope=openid profile email" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id_token"])')"
  [ -n "$id_token" ] || die "拿不到 $username 的 Casdoor id_token"
  access_token="$(curl -s -X POST "$IAM_URL/api/iam/token" \
    -H "Content-Type: application/json" \
    -d "{\"casdoor_id_token\": \"$id_token\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
  [ -n "$access_token" ] || die "$username 换应用 JWT 失败"
  echo "$access_token"
}

sub_of() { # username -> Casdoor 内部用户 id（不是用户名），查不到回显空串
  _ensure_casdoor_admin
  curl -b "$COOKIE_JAR" -s "$CASDOOR_URL/api/get-user?id=brickkit/$1" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(d["id"] if d else "")'
}

# infra-authz 的 bundle 是各组件每 ~15s 轮询一次拉进内存的——Makefile
# 链式调用刚跑完 infra-authz 的 seed，立刻拿 JWT 调自己的 REST 接口有
# 真实的竞态窗口，等 18 秒让 bundle 刷新到最新授权。
wait_bundle_refresh() {
  echo "   等 18 秒，让本组件的权限 bundle 轮询到最新授权……"
  sleep 18
}

psqlx() { docker exec -i be-postgres psql -U postgres -d brickkit_db -v ON_ERROR_STOP=1 "$@"; }
idfor() { psqlx -tA -q -c "SET search_path TO $1; SELECT result_id FROM command_idempotency WHERE idempotency_key = '$2';"; }
