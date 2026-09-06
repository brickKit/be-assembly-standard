#!/usr/bin/env bash
# make <res>-up / <res>-down 的实现。res 是单个资源名，或组名 obs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TARGET="${1:?用法：optional.sh <资源名|obs> <up|down>}"
ACTION="${2:?用法：optional.sh <资源名|obs> <up|down>}"

# 解析成一批行：obs 是 profile 组，其余是单个资源名
if [[ "$TARGET" == obs ]]; then
  mapfile -t ROWS < <(read_rows "profile:obs")
else
  mapfile -t ROWS < <(read_rows "$TARGET")
fi
((${#ROWS[@]})) || die "resources.tsv 里没有 ${TARGET}"

# 可选资源专用。默认资源请用 make up / make down
for row in "${ROWS[@]}"; do
  [[ "$(row_field "$row" default)" == no ]] \
    || die "${TARGET} 是默认资源，请用 make up / make down"
done

PROJECT="$(row_field "${ROWS[0]}" project)"
FILE="$(row_field "${ROWS[0]}" compose_file)"
PROFILE="$(row_field "${ROWS[0]}" profile)"

if [[ "$ACTION" == up ]]; then
  ensure_net

  # ── 互斥校验：同一 mutex 组里已经有别的成员在跑就报错 ──
  for row in "${ROWS[@]}"; do
    grp="$(row_field "$row" mutex)"; me="$(row_field "$row" name)"
    [[ "$grp" == "-" ]] && continue
    while IFS= read -r other; do
      oname="$(row_field "$other" name)"
      ocont="$(row_field "$other" container)"
      [[ "$oname" == "$me" || "$(row_field "$other" mutex)" != "$grp" ]] && continue
      if [[ "$(docker inspect -f '{{.State.Status}}' "$ocont" 2>/dev/null)" == running ]]; then
        die "${me} 与 ${oname} 属于同一互斥组「${grp}」，同一环境只能装一个。
   先关掉它：make ${oname}-down（若它是默认资源，说明你要换的是默认实现，
   还要同步改 brickkit.yaml 的 resources[].engine 或那份 compose）"
      fi
    done < <(read_rows all)
  done

  # ── 端口预检：只查「容器还不存在」的那几个 ──
  # ⚠️ 实测发现：容器已存在时（比如上次启动失败、这次要用改过的配置重建），
  # 它自己发布的端口会被 port_owner 当成"被占用"报出来——因为 port_owner
  # 判断"是不是自己"靠 docker ps 里的容器名匹配，而调用方在容器已存在时
  # 传的 cont 本该被正确排除，可这里根本没检查"容器存在与否"就直接查了，
  # 于是任何"容器还在、只是没起来 / 要被 compose recreate"的重跑场景都会
  # 被误判成端口冲突，报错文案还是"占用者不明"。check.sh 与 up.sh 都遵循
  # "容器已存在就交给 compose 去处理，只有容器完全不存在时才查端口"这个
  # 模式，这里补齐同一条。
  for row in "${ROWS[@]}"; do
    cont="$(row_field "$row" container)"
    docker inspect "$cont" >/dev/null 2>&1 && continue
    IFS=',' read -ra ps <<< "$(row_field "$row" host_ports)"
    for p in "${ps[@]}"; do
      o="$(port_owner "$p" "$cont")"
      [[ -n "$o" ]] && die "$(row_field "$row" name)：端口 ${p} 已被 ${o} 占用"
    done
  done

  svcs=(); for row in "${ROWS[@]}"; do svcs+=("$(row_field "$row" service)"); done
  docker compose --env-file "$ROOT/.env" -p "$PROJECT" -f "$FILE" --profile "$PROFILE" \
    up -d --wait --wait-timeout 180 "${svcs[@]}" \
    || die "启动 ${TARGET} 失败"
  echo "${C_GRN}✓ ${TARGET} 已开启${C_OFF}"

elif [[ "$ACTION" == down ]]; then
  svcs=(); for row in "${ROWS[@]}"; do svcs+=("$(row_field "$row" service)"); done
  docker compose --env-file "$ROOT/.env" -p "$PROJECT" -f "$FILE" --profile "$PROFILE" \
    rm -sf "${svcs[@]}" || die "关闭 ${TARGET} 失败"
  echo "${C_GRN}✓ ${TARGET} 已关闭（volume 保留）${C_OFF}"
else
  die "ACTION 只能是 up 或 down"
fi
