#!/usr/bin/env bash
# Measures the per-request cost of an edge session layer on Traefik v3.0.4 (the project's pinned image): a = direct,
# b = Yaegi middleware, c = compiled sidecar behind a hairpin. Paired, alternating rounds in performance power mode
# (restored at the end, also when stopped); d = the same sidecar in front of Traefik (no hairpin).
# Usage: run.sh <out dir> [rounds] [rate] [seconds] [paths, default "a b c"]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); out=$1; rounds=${2:-3}; rate=${3:-2000}; secs=${4:-20}; paths=(${5:-a b c})
mkdir -p "$out"
prev=$(powerprofilesctl get)
cleanup() { docker rm -f edgecost-traefik >/dev/null 2>&1 || true; kill $(jobs -p) 2>/dev/null || true; powerprofilesctl set "$prev"; }
trap cleanup EXIT
powerprofilesctl set performance
echo "power: $(powerprofilesctl get) (was $prev)" | tee "$out/power.txt"
uptime | tee "$out/uptime-before.txt"
"$here/bin-backend" "$here/token.txt" 127.0.0.1:18100 & bpid=$!
"$here/bin-proxy" "$here/token.txt" http://127.0.0.1:18081 127.0.0.1:18090 & ppid=$!
docker run -d --name edgecost-traefik --network host \
  -v "$here/traefik:/etc/traefik:ro" -v "$here/plugin:/plugins-local:ro" \
  traefik:v3.0.4@sha256:a208c74fd80a566d4ea376053bff73d31616d7af3f1465a7747b8b89ee34d97e >/dev/null
for i in $(seq 1 50); do curl -sf -o /dev/null --cookie be_session=measurement-session-cookie http://127.0.0.1:18080/b && break; sleep 0.2; done
tpid=$(docker inspect -f '{{.State.Pid}}' edgecost-traefik)
docker exec edgecost-traefik traefik version > "$out/traefik-version.txt" 2>&1 || true
# preconditions: each path answers 200 with the token injected; without the cookie b and c answer 401
for p in a b c; do test "$(curl -s -o /dev/null -w '%{http_code}' --cookie be_session=measurement-session-cookie http://127.0.0.1:18080/$p)" = 200; done
for p in b c; do test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/$p)" = 401; done
test "$(curl -s -o /dev/null -w '%{http_code}' --cookie be_session=measurement-session-cookie http://127.0.0.1:18090/c)" = 200; test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18090/c)" = 401
echo "preconditions ok" | tee "$out/preconditions.txt"
cpu() { awk '{print $14+$15}' /proc/$1/stat; }  # utime+stime in clock ticks
tick=$(getconf CLK_TCK)
for p in a b c; do "$here/bin-load" -url http://127.0.0.1:18080/$p -rate "$rate" -d 3s -label warm-$p >> "$out/warmup.jsonl"; done
"$here/bin-load" -url http://127.0.0.1:18090/c -rate "$rate" -d 3s -label warm-d >> "$out/warmup.jsonl"
for r in $(seq 1 "$rounds"); do
  k=$(( (r - 1) % ${#paths[@]} )); order=("${paths[@]:k}" "${paths[@]:0:k}")
  for p in "${order[@]}"; do
    url=http://127.0.0.1:18080/$p; [ "$p" = d ] && url=http://127.0.0.1:18090/c
    t0=$(cpu "$tpid"); x0=$(cpu "$ppid"); k0=$(cpu "$bpid")
    line=$("$here/bin-load" -url "$url" -rate "$rate" -d "${secs}s" -label "$p")
    t1=$(cpu "$tpid"); x1=$(cpu "$ppid"); k1=$(cpu "$bpid")
    echo "{\"round\":$r,\"path\":\"$p\",\"tick\":$tick,\"traefik_ticks\":$((t1-t0)),\"proxy_ticks\":$((x1-x0)),\"backend_ticks\":$((k1-k0)),\"load\":$line}" | tee -a "$out/runs.jsonl"
  done
done
uptime | tee "$out/uptime-after.txt"
