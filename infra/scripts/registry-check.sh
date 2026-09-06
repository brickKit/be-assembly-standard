#!/usr/bin/env bash
# 端口册与 schema 册的自洽校验。判据已经搬进 be-ops（tools/be-ops/internal/
# registry），本脚本退休为薄壳——阶段一 Task 8。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BEOPS_BIN="$ROOT/tools/be-ops/build/be-ops"

if [[ ! -x "$BEOPS_BIN" ]]; then
  echo "▸ 编译 be-ops（首次运行或源码有更新）" >&2
  (cd "$ROOT/tools/be-ops" && go build -o build/be-ops ./cmd/be-ops)
fi

exec "$BEOPS_BIN" registry check --root "$ROOT"
