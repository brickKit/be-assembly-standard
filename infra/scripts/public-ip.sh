#!/usr/bin/env bash
# 查当前公网出口 IP——家用宽带的公网 IP 会变，钉钉互动卡片回调地址这类
# "要把本机端口暴露给外网"的场景，每次用之前都得先查一次，不能假设跟
# 上次一样。多个查询源轮流试，第一个答上来的算数（避免单一第三方服务
# 挂了就用不了）。
set -uo pipefail

for url in "https://ifconfig.me" "https://icanhazip.com" "https://ipinfo.io/ip" "https://api.ipify.org"; do
  ip="$(curl -fsS --max-time 3 "$url" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    printf '%s\n' "$ip"
    exit 0
  fi
done

echo "✗ 查不到公网 IP——四个查询源都没答上来，检查一下网络" >&2
exit 1
