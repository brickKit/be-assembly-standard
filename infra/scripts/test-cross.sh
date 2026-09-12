#!/usr/bin/env bash
# 组件局部测试：只跑一个组件自己的测试，把它的强依赖 gRPC 端点指向真实
# 在跑的依赖容器——依赖不必是全套 brickkit up，只要"这个组件连同强依赖
# 树"在跑就行（§1.5 原则一）。跑完那几条平时 requireE2EEnv 直接 skip 掉
# 的 L4 跨组件测试。
#
# 为什么要转发器：平台不把 gRPC 额外端口映射到宿主机
# （brickKit internal/compose/local.go，导读第 1/14 条），宿主机上的 go
# test 进程够不到 mdm-customer:9090。所以给每条强依赖起一个 alpine/socat
# 容器：宿主机 127.0.0.1:2xxxx ← 依赖容器的 gRPC 端口（走 brickkit 网络
# 的 DNS 名）。测试进程照常在宿主机上跑（用宿主机 Go cache、-race 正常、
# 输出正常），只有转发器是容器，跑完就删。
#
# 用法：test-cross.sh <仓库名> [传给 go test 的额外参数…]
#   test-cross.sh crm-opportunity
#   test-cross.sh crm-opportunity -run TestCreateOpportunity -v
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${1:?用法：test-cross.sh <仓库名> [go test 额外参数…]}"
shift || true

DIR="$ROOT/components/$(echo "$REPO" | sed 's#-#/#')"   # 只换第一个 -：infra-bff-mobile → infra/bff-mobile
[ -d "$DIR" ] || { echo "✗ 找不到组件目录：$DIR" >&2; exit 1; }
[ -f "$DIR/component.yaml" ] || { echo "✗ $DIR 下没有 component.yaml" >&2; exit 1; }

NET="${BRICKKIT_NET:-brickkit-$(basename "$ROOT")-net}"
docker network inspect "$NET" >/dev/null 2>&1 || {
	echo "✗ docker 网络 $NET 不存在——先 brickkit up（整套，或只装这个组件+强依赖树）" >&2
	exit 1
}

# 强依赖列表：component.yaml 的 dependencies.components 段里的 scope/name（去掉 @版本、去掉 optional 包装）
mapfile -t DEPS < <(awk '
	/^dependencies:/ {ind=1}
	ind && /^  components:/ {inc=1; next}
	inc && /^  [a-z]/ {inc=0}
	inc && match($0, /[a-z][a-z_-]*\/[a-z][a-z_-]*@/) { print substr($0, RSTART, RLENGTH-1) }
' "$DIR/component.yaml")

# .env 里的 POSTGRES_PASSWORD 用于拼默认 TEST_PG_DSN（已在环境里就不覆盖）
#
# ⚠️ 只能部分隔离：这里默认指到 brickkit_test_db，隔离的是"这个组件
# 自己写自己 schema"那部分；但 test-cross 的整个意义就是打真实在跑的
# 依赖容器（下面转发器桥的那些强依赖 gRPC 端点），那些容器连的是真机
# 部署用的 brickkit_db（brickkit.yaml 的资源绑定写死的，跟这个环境变量
# 无关）——如果被测流程会通过真实 gRPC 调用让依赖容器产生新数据（比如
# 真的建一个客户），那条数据还是会落进 brickkit_db，不受这里影响。
#
# ⚠️ 这条注释曾经只停在"提醒"这一步，没有配套的环境变量——真实踩过的
# 坑：erp-sales 的 confirm_test.go/opportunity_won_test.go 有两个辅助
# 函数（receiveRealStock/getRealBalance）直接读写 erp-inventory 的
# schema，图省事传的是 TEST_PG_DSN 那个连接，结果真实 Reserve 调用
# （打真实在跑的 erp-inventory 容器，读的是 brickkit_db）永远看不到写
# 进 brickkit_test_db 的库存——TestConfirmOrder_真实happy_path 这条
# 全组件最核心的 TCC happy-path 测试因此长期报"库存不足"，没人发现是
# 因为很少有人真的单独重跑 test-cross。新增 REAL_PG_DSN，专门给这类
# "需要让真实依赖容器看到这批数据"的测试辅助函数用，不跟 TEST_PG_DSN
# 混用。
if [ -f "$ROOT/.env" ]; then set -a; . "$ROOT/.env"; set +a; fi
: "${TEST_PG_DSN:=postgres://postgres:${POSTGRES_PASSWORD:-postgres}@localhost:5432/brickkit_test_db?sslmode=disable}"
: "${REAL_PG_DSN:=postgres://postgres:${POSTGRES_PASSWORD:-postgres}@localhost:5432/brickkit_db?sslmode=disable}"
: "${TEST_NATS_URL:=nats://localhost:4222}"

FWDS=()
ENVS=()
cleanup() { [ ${#FWDS[@]} -gt 0 ] && docker rm -f "${FWDS[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for dep in "${DEPS[@]}"; do
	grpc_port="$(awk -F'\t' -v c="$dep" '$2==c {print $4}' "$ROOT/registry/ports.tsv")"
	[ -n "$grpc_port" ] || { echo "✗ registry/ports.tsv 里找不到 $dep 的 grpc 端口" >&2; exit 1; }

	slug="$(echo "$dep" | tr '/' '-')"                       # mdm/customer → mdm-customer
	cname="$(docker ps --filter "name=${NET%-net}-${slug}-" --format '{{.Names}}' | head -1)"
	[ -n "$cname" ] || {
		echo "✗ 依赖容器没在跑：$dep（找不到名字含 ${NET%-net}-${slug}- 的容器）——先把它 brickkit up 起来" >&2
		exit 1
	}

	host_port=$((20000 + grpc_port - 9000))                  # 9090 → 20090，走 2xxxx 段（导读第 14 条）
	fwd="testcross-fwd-${slug}-$$"
	docker run -d --rm --name "$fwd" --network "$NET" -p "127.0.0.1:${host_port}:${host_port}" \
		alpine/socat "tcp-listen:${host_port},fork,reuseaddr" "tcp-connect:${cname}:${grpc_port}" >/dev/null || {
		echo "✗ 起 socat 转发器失败：$dep" >&2; exit 1
	}
	FWDS+=("$fwd")

	ev="$(echo "$dep" | tr 'a-z/-' 'A-Z__')_GRPC_ENDPOINT"   # mdm/customer → MDM_CUSTOMER_GRPC_ENDPOINT
	ENVS+=("$ev=http://localhost:${host_port}")
done

echo "▶ 局部测试 $REPO"
if [ ${#ENVS[@]} -eq 0 ]; then
	echo "    （无强依赖，等价于 make test）"
else
	for e in "${ENVS[@]}"; do echo "    $e"; done
	sleep 1   # 给 socat 一点起步时间
fi

cd "$DIR"
env "${ENVS[@]}" TEST_PG_DSN="$TEST_PG_DSN" REAL_PG_DSN="$REAL_PG_DSN" TEST_NATS_URL="$TEST_NATS_URL" \
	go test ./backend/... -race -count=1 "$@"
