#!/usr/bin/env bash
# make up 的实现。两阶段：先整体预检，全过才启动。已就绪的跳过，不符的报错中止
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ensure_net

# ── 阶段一：整体预检 ───────────────────────────────────────────
# 只有「不符」才拦（镜像/端口/健康/端口被占）；「缺失」是正常的，那正是要启动的
echo "▸ 阶段一：预检"
BLOCK=0
while IFS= read -r row; do
  name="$(row_field "$row" name)"
  cont="$(row_field "$row" container)"
  want_img="$(row_field "$row" image)"
  want_ports="$(row_field "$row" host_ports)"

  if docker inspect "$cont" >/dev/null 2>&1; then
    got_img="$(docker inspect -f '{{.Config.Image}}' "$cont")"
    if [[ "$got_img" != "$want_img" ]]; then
      echo "  ${C_RED}✗ ${name}：镜像不符${C_OFF}  期望 ${want_img} / 实际 ${got_img}"
      BLOCK=1
    fi
    mapfile -t published < <(docker port "$cont" 2>/dev/null | sed 's/.*:\([0-9]\+\)$/\1/' | sort -u)
    IFS=',' read -ra ps <<< "$want_ports"
    for p in "${ps[@]}"; do
      printf '%s\n' "${published[@]}" | grep -qx "$p" || {
        echo "  ${C_RED}✗ ${name}：端口 ${p} 未发布${C_OFF}"; BLOCK=1; }
    done
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cont")"
    [[ "$health" == unhealthy ]] && {
      echo "  ${C_RED}✗ ${name}：健康检查 unhealthy${C_OFF}"; BLOCK=1; }
  else
    IFS=',' read -ra ps <<< "$want_ports"
    for p in "${ps[@]}"; do
      o="$(port_owner "$p" "$cont")"
      [[ -n "$o" ]] && {
        echo "  ${C_RED}✗ ${name}：端口 ${p} 已被 ${o} 占用${C_OFF}"; BLOCK=1; }
    done
  fi
done < <(read_rows default)

if ((BLOCK)); then
  cat <<'HINT'

✗ 预检未通过，一个容器都没有启动（避免半开状态）。
  本项目不会替你 stop / rm 任何容器。请自己排查后重跑 make up：
    docker ps -a --filter name=be-
    docker logs --tail 50 <容器名>
HINT
  exit 1
fi
echo "  ${C_GRN}✓ 预检通过${C_OFF}"

# ── 阶段二：启动。compose up -d 对已就绪的容器是幂等的，不会重建 ──
echo "▸ 阶段二：启动"
docker compose --env-file "$ROOT/.env" -p be-infra -f infra/docker-compose.infra.yml up -d --wait --wait-timeout 180 \
  || die "compose up 失败。跑 make status 与 docker logs 看是哪个"

echo "▸ 阶段三：复检"
exec bash "$(dirname "${BASH_SOURCE[0]}")/check.sh" default
