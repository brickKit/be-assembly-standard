#!/usr/bin/env bash
# 一键重跑 r1-09：起一次性 Casdoor → 建组织/应用/用户 → 真浏览器 PKCE → 无浏览器补充用例 → 格式对比 → 全部删掉。
# PW_CORE / PW_CHROMIUM 指向本机已有的 playwright-core 与 Chromium（见 README「环境与版本」）。
set -euo pipefail
cd "$(dirname "$0")"
trap './down.sh; kill $SPA_PID 2>/dev/null || true' EXIT
./up.sh
python3 setup.py
python3 spa/serve.py & SPA_PID=$!
sleep 1
mkdir -p output
node browser.cjs | tee output/browser.out
python3 flow.py | tee output/flow.out
python3 formats.py | grep tokenFormat | tee output/formats.out
curl -s http://localhost:38000/.well-known/openid-configuration > output/discovery.json
