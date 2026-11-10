#!/usr/bin/env bash
# C1 E6: every component onto be-sdk-go alpha.121 (one SDK version system-wide), in dependency order.
cd "$(dirname "$0")/../../../.." || exit 1
echo $$ > dev/rebuild/c1-data/sdk121/run.pid
export PYTHONDONTWRITEBYTECODE=1
python3 dev/rebuild/experiment-scripts/sdk-unify.py --sdk v3.0.0-alpha.121 \
  --line "be-sdk-go alpha.121（全系统同一个 SDK 版本；sectest 的授权组件替身答 CheckLinkChange 与 Administrators）" \
  --notes "be-sdk-go alpha.121：全系统同一个 SDK 版本（C1 的员工组件上线前一起换）。" \
  --subject "be-sdk-go alpha.121; version {version}" "$@"
echo "SDK121 RUN-END $?"
