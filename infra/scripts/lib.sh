#!/usr/bin/env bash
# 基础资源脚本公用函数。判据真相源是 infra/resources.tsv
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TSV="$ROOT/infra/resources.tsv"
NET="be-net"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'

die() { printf '%s\n' "${C_RED}✗ $*${C_OFF}" >&2; exit 1; }

# 列名 → 序号。改 tsv 列顺序时只改这里
col_of() {
  case "$1" in
    name) echo 1;; project) echo 2;; compose_file) echo 3;; service) echo 4;;
    container) echo 5;; image) echo 6;; host_ports) echo 7;; default) echo 8;;
    profile) echo 9;; mutex) echo 10;;
    *) die "未知列名：$1";;
  esac
}

# row_field "<制表符分隔的一行>" <列名>
row_field() {
  local row="$1" idx; idx="$(col_of "$2")"
  printf '%s' "$row" | cut -d$'\t' -f"$idx"
}

# read_rows <mode>  →  逐行输出匹配的 tsv 行
#   default      仅 default=yes
#   all          全部
#   profile:<p>  该 profile 的全部
#   <name>       单个资源
read_rows() {
  local mode="$1"
  [[ -f "$TSV" ]] || die "找不到 $TSV"
  while IFS= read -r row; do
    [[ -z "$row" || "$row" == \#* ]] && continue
    local name def prof
    name="$(row_field "$row" name)"
    def="$(row_field "$row" default)"
    prof="$(row_field "$row" profile)"
    case "$mode" in
      default)   [[ "$def" == yes ]] && printf '%s\n' "$row";;
      all)       printf '%s\n' "$row";;
      profile:*) [[ "$prof" == "${mode#profile:}" ]] && printf '%s\n' "$row";;
      *)         [[ "$name" == "$mode" ]] && printf '%s\n' "$row";;
    esac
  done < "$TSV"
}

# port_owner <宿主机端口> <自己的容器名>  →  占用者描述，空表示没人占
#
# ⚠️ 实测发现两处需要修的：
# ① docker ps 对端口范围的格式是 "9000-9001->9000-9001"（不是 "9000->9000"），
#    原正则 ":$port->" 只匹配单端口发布，遇到范围端口（如别的项目用
#    `-p 9000-9001:9000-9001` 起的容器）会漏判，退化到 ss 分支。
#    改成允许可选的 "-<数字>" 前缀。
# ② ss -p 对不是当前用户拥有的进程（docker-proxy 通常是 root）
#    会静默拿不到进程名——这不是本机特例，是 ss 的权限模型：
#    非 root 用户看不到别人进程的名字，不报错，只是那一列是空的。
#    不处理的话输出是「宿主机进程 」（末尾一个空格，后面什么都没有），
#    对着这行字部署人员会以为脚本坏了。改成显式说明「查不到名字」。
port_owner() {
  local port="$1" self="$2" owner="" name=""
  owner="$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null \
           | awk -F'\t' -v p=":$port(-[0-9]+)?->" -v self="$self" \
                 '$2 ~ p && $1 != self {print "容器 " $1; exit}')"
  if [[ -z "$owner" ]] && command -v ss >/dev/null 2>&1; then
    name="$(ss -ltnpH 2>/dev/null | awk -v p=":$port$" '$4 ~ p {print $6; exit}')"
    if [[ -n "$name" ]]; then
      owner="宿主机进程 $name"
    elif ss -ltnH 2>/dev/null | awk -v p=":$port$" '$4 ~ p {found=1} END{exit !found}'; then
      owner="宿主机某进程（权限不足看不到名字，试 sudo ss -ltnp | grep :$port）"
    fi
  fi
  printf '%s' "$owner"
}

ensure_net() {
  if ! docker network inspect "$NET" >/dev/null 2>&1; then
    docker network create "$NET" >/dev/null
    printf '%s\n' "${C_DIM}已创建 external network $NET${C_OFF}"
  fi
}

net_ok() { docker network inspect "$NET" >/dev/null 2>&1; }
