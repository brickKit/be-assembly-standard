#!/usr/bin/env bash
# make check / make check-all 的实现。只读，不改任何状态
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-default}"
FAIL=0

printf '%-16s %-34s %-22s %s\n' "资源" "镜像" "端口" "状态"
printf '%s\n' "$(printf '─%.0s' {1..100})"

while IFS= read -r row; do
  name="$(row_field "$row" name)"
  cont="$(row_field "$row" container)"
  want_img="$(row_field "$row" image)"
  want_ports="$(row_field "$row" host_ports)"
  is_def="$(row_field "$row" default)"

  # 容器存在吗
  if ! docker inspect "$cont" >/dev/null 2>&1; then
    # 不存在时也要查端口有没有被别人占——这是「一键开启会不会失败」的预告
    squat=""
    IFS=',' read -ra ps <<< "$want_ports"
    for p in "${ps[@]}"; do
      o="$(port_owner "$p" "$cont")"
      [[ -n "$o" ]] && squat+="${p} 被 ${o}; "
    done
    if [[ -n "$squat" ]]; then
      printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
        "${C_RED}✗ 端口被占：${squat%; }${C_OFF}"
      FAIL=1
    elif [[ "$is_def" == yes ]]; then
      printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
        "${C_YEL}○ 缺失（make up 会拉起）${C_OFF}"
    else
      printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
        "${C_DIM}－ 未启用（可选）${C_OFF}"
    fi
    continue
  fi

  # 镜像对不对
  got_img="$(docker inspect -f '{{.Config.Image}}' "$cont")"
  msgs=()
  if [[ "$got_img" != "$want_img" ]]; then
    msgs+=("镜像不符：实际 ${got_img}")
  fi

  # 端口对不对
  mapfile -t published < <(docker port "$cont" 2>/dev/null | sed 's/.*:\([0-9]\+\)$/\1/' | sort -u)
  IFS=',' read -ra ps <<< "$want_ports"
  for p in "${ps[@]}"; do
    if ! printf '%s\n' "${published[@]}" | grep -qx "$p"; then
      msgs+=("端口 ${p} 未发布")
    fi
  done

  # 健康与运行状态
  state="$(docker inspect -f '{{.State.Status}}' "$cont")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cont")"
  [[ "$state" != running ]] && msgs+=("状态 ${state}")
  [[ "$health" == unhealthy ]] && msgs+=("健康检查 unhealthy")
  [[ "$health" == starting ]] && msgs+=("健康检查仍在 starting")

  if ((${#msgs[@]})); then
    printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
      "${C_RED}✗ $(IFS='；'; echo "${msgs[*]}")${C_OFF}"
    FAIL=1
  else
    printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
      "${C_GRN}✓ healthy${C_OFF}"
  fi
done < <(read_rows "$MODE")

printf '%s\n' "$(printf '─%.0s' {1..100})"
if net_ok; then
  printf 'network be-net  %s\n' "${C_GRN}✓${C_OFF}"
else
  printf 'network be-net  %s\n' "${C_RED}✗ 不存在（跑 make net）${C_OFF}"; FAIL=1
fi

if ((FAIL)); then
  cat <<'HINT'

✗ 有资源不符。本项目不会替你 stop / rm 任何容器——请自己排查后重跑：
    docker ps -a --filter name=be-
    docker logs --tail 50 <容器名>
  端口被非本项目容器占用时，先确认那个容器是不是别的项目在用。
HINT
  exit 1
fi
printf '\n%s\n' "${C_GRN}✓ 全部基础资源就绪${C_OFF}"
