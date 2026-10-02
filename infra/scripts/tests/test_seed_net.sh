#!/usr/bin/env bash
# seed-net.sh 的 component_version / service_name / service_host：用 v1 的 brickkit.yaml 与 compose.yaml 片段验证。
set -euo pipefail
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.brickkit/generated" "$T/infra/scripts/lib"
cp "$(dirname "$0")/../lib/seed-net.sh" "$T/infra/scripts/lib/"
cat > "$T/brickkit.yaml" <<'Y'
project: demo
components:
  - id: be/go-core
    version: 1.0.0
    source: local-shells
  - id: mdm/customer
    version: 2.0.0
    source: local-dev
  - id: infra/authz
    version: 2.0.0
    source: local-dev
Y
cat > "$T/.brickkit/generated/compose.yaml" <<'Y'
services:
  be-go-core-1-0-0:
    networks:
      brickkit-demo-net:
        aliases: [mdm-customer-2-0-0]
  infra-authz-2-0-0:
    networks: [brickkit-demo-net]
Y
ROOT="$T"; set +e
# shellcheck disable=SC1091
source "$T/infra/scripts/lib/seed-net.sh"
set -e
eq() { [ "$1" = "$2" ] || { echo "✗ 期望 $2，实际 $1"; exit 1; }; }
eq "$(component_version be/go-core)" 1.0.0
eq "$(component_version mdm/customer)" 2.0.0
eq "$(service_name mdm/customer)" mdm-customer-2-0-0
eq "$(service_host mdm/customer)" be-go-core-1-0-0
eq "$(service_host infra/authz)" infra-authz-2-0-0
# 解析失败必须报错退出（不再静默退回推断值）
printf 'services: [unclosed\n' > "$T/bad.yaml"
if err="$( (COMPOSE_FILE_GENERATED="$T/bad.yaml"; service_host mdm/customer) 2>&1 )"; then
  echo "✗ 坏 compose 文件应当报错退出"; exit 1
fi
echo "$err" | grep -q "service_host" || { echo "✗ 报错信息应点名 service_host: $err"; exit 1; }
echo "✓ seed-net 测试通过"
