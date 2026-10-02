#!/usr/bin/env bash
# 单组件（或外壳）真机验证：build → 只起闭包 → 迁移/健康/鉴权检查 → 跨组件测试 →（可选）focus → 收尾，最后打印汇总表。
# 持项目锁执行（build/up/down/local 与 deploy.verify.yaml 都是项目共享状态）。任何一项 FAIL → 退出 1。
#
# 用法：bash infra/scripts/verify-component.sh <id>        （make verify ID=<id> [ROUTE=…] [FOCUS=1] [KEEP=1]）
#   环境变量：
#     ROUTE='<路径>' 或 '<METHOD> <路径>'  受保护路由（省略方法时 GET）；不带 token 期望 401/503，带 token 期望 200
#     FOCUS=1        容器形态之后再跑一次 brickkit up --focus <id>（宿主机进程），结束后 brickkit local off
#     KEEP=1         不收尾：容器留着（用完 brickkit down -f deploy.verify.yaml）；focus 进程照样停掉，本地模式照样关、
#                    deploy.local.yaml 照样还原
#                    （FOCUS / KEEP 只有值为 1 才生效，0 或其它值等于没设）
#   中断（Ctrl+C、SIGTERM、超时）时 EXIT 陷阱照样收尾：停 focus 进程组、local off、还原 deploy.local.yaml；
#     除非 KEEP=1，再 down、删 deploy.verify.yaml
#     FORCE_BUILD=1  本组件的镜像 brickkit build --force（版本没变但代码改过时）
#     OUT=<目录>     输出目录，默认 $BE_SCRATCH/verify/<repo>-<时间>（没有 BE_SCRATCH 时用项目的 build/verify/）
#     BE_ROOT        项目根（默认本仓库；测试用）
#   --deploy-only <文件>  只按闭包生成 deploy.verify.yaml 形态的文件并打印闭包，不碰 Docker（测试与预览用）
set -uo pipefail
# 先核对 brickkit 版本（不对就不等项目锁、直接退出 2）；--deploy-only 不调 brickkit，不查
[ "${2:-}" = --deploy-only ] || { source "$(dirname "${BASH_SOURCE[0]}")/lib/require-brickkit.sh"; require_brickkit; }
[ -n "${BE_PROJECT_LOCK_HELD:-}" ] || [ "${2:-}" = --deploy-only ] \
  || exec bash "$(dirname "${BASH_SOURCE[0]}")/project-lock.sh" -- bash "${BASH_SOURCE[0]}" "$@"

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BE_ROOT:-$(cd "$S/../.." && pwd)}"
ID="${1:-}"
[[ "$ID" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] || { echo "用法：verify-component.sh <scope>/<name> [--deploy-only <文件>]" >&2; exit 2; }
cd "$ROOT" || exit 1
REPO="${ID//\//-}"

# ---------- 闭包与 deploy.verify.yaml（Python：读 brickkit.yaml、各组件 component.yaml、deploy.yaml） ----------
# 输出可 eval 的变量：VER SVC PORT IS_SHELL PROJECT KEEP_IDS（id@ver 列表）MEMBERS（外壳成员 id@ver|svc|port 列表）
plan() {
  python3 - "$ROOT" "$ID" "$1" <<'PY'
import copy, pathlib, shlex, sys, yaml
root, target, out = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
load = lambda p: yaml.safe_load(p.read_text(encoding="utf-8")) or {}
bk = load(root / "brickkit.yaml")
entries = bk.get("components") or []
default = {c["id"]: str(c["version"]) for c in entries if not c.get("requiredBy")}
in_project = {c["id"] for c in entries}
if target not in default:
    sys.exit(f"✗ {target} 不在 brickkit.yaml 里——先 make integrate ID={target}")

def manifest(cid, ver):
    for base in ("components", "shell"):
        p = root / base / cid / "component.yaml"
        if p.exists():
            m = load(p)
            if str((m.get("metadata") or {}).get("version")) == ver:
                return m
    p = root / ".brickkit" / "manifests" / cid / ver / "component.yaml"
    if p.exists():
        return load(p)
    sys.exit(f"✗ 找不到 {cid}@{ver} 的 component.yaml（本地源或 .brickkit/manifests/）")

def split(ref):
    cid, _, ver = ref.partition("@")
    return cid, ver or default.get(cid, "")

def svc(cid, ver):
    return f"{cid}-{ver}".lower().replace("/", "-").replace(".", "-")

def closure(start):
    seen, todo = set(), list(start)
    while todo:
        cid, ver = todo.pop()
        if (cid, ver) in seen:
            continue
        seen.add((cid, ver))
        m = manifest(cid, ver)
        for d in (m.get("dependencies") or {}).get("components") or []:
            ref, optional = (d, False) if isinstance(d, str) else (d["id"], bool(d.get("optional")))
            dcid, dver = split(ref)
            if optional and dcid not in in_project:
                continue
            todo.append((dcid, dver))
        for mem in (m.get("shell") or {}).get("members") or []:
            todo.append(split(mem))
    return seen

tver = default[target]
tm = manifest(target, tver)
for e in (load(root / "deploy.yaml").get("components") or []):
    for x in [e] + list(e.get("members") or []):
        if split(x["id"]) == (target, tver) and x.get("mode") == "disable":
            sys.exit(f"✗ {target} 在 deploy.yaml 里是 mode: disable——verify 不改团队的决定；要验证它先去掉这一行")
start = [(target, tver)] + [(c, default[c]) for c in ("infra/authz", "infra/iam-casdoor") if c in default]
keep = closure(start)

dep = load(root / "deploy.yaml")
top = dep.get("components") or []
def ref_of(e):
    return split(e["id"])
changed = True
while changed:  # 含闭包成员的外壳整个保留：它托管的其它成员及其依赖也得能跑
    changed = False
    for e in top:
        mems = [ref_of(m) for m in e.get("members") or []]
        if mems and (ref_of(e) in keep or any(m in keep for m in mems)):
            new = closure([ref_of(e)] + mems) - keep
            if new:
                keep |= new
                changed = True

v = copy.deepcopy(dep)
disabled = []
for e in v.get("components") or []:
    if ref_of(e) in keep or any(ref_of(m) in keep for m in e.get("members") or []):
        # 被别人依赖的组件（如 mdm/customer）在"跟随上层"规则下不会自己启动：闭包里的顶层条目显式 enabled
        e.setdefault("mode", "enabled")
        continue
    e["mode"] = "disable"
    disabled.append(e["id"])
    for m in e.get("members") or []:  # 外壳停掉时成员会各自独立部署：一起停
        m["mode"] = "disable"
with open(out, "w", encoding="utf-8") as f:
    f.write(f"# 由 infra/scripts/verify-component.sh 为 {target} 生成（不提交）：deploy.yaml 的副本，\n"
            f"# 与 {target} 的依赖闭包（及已加入项目的 infra/authz、infra/iam-casdoor）无交集的条目写成 mode: disable，\n"
            f"# 闭包里没写 mode 的顶层条目写成 mode: enabled。\n")
    yaml.safe_dump(v, f, allow_unicode=True, sort_keys=False)

members = [f"{c}@{ver}|{svc(c, ver)}|{(manifest(c, ver).get('deployment') or {}).get('port', '')}"
           for c, ver in (split(x) for x in (tm.get("shell") or {}).get("members") or [])]
print(f"VER={shlex.quote(tver)}")
print(f"SVC={shlex.quote(svc(target, tver))}")
print(f"PORT={shlex.quote(str((tm.get('deployment') or {}).get('port', '')))}")
print(f"IS_SHELL={1 if 'shell' in tm else 0}")
print(f"PROJECT={shlex.quote(str(bk.get('project', root.name)))}")
print(f"KEEP_IDS={shlex.quote(' '.join(sorted(f'{c}@{ver}' for c, ver in keep)))}")
print(f"DISABLED={shlex.quote(' '.join(disabled))}")
print(f"MEMBERS={shlex.quote(' '.join(members))}")
mig = bool(tm.get("migration")) or any(manifest(*split(x)).get("migration") for x in (tm.get("shell") or {}).get("members") or [])
print(f"HAS_MIG={1 if mig else 0}")
PY
}

if [ "${2:-}" = --deploy-only ]; then
  [ -n "${3:-}" ] || { echo "用法：verify-component.sh <id> --deploy-only <输出文件>" >&2; exit 2; }
  plan "$3"; exit $?
fi

VF="$ROOT/deploy.verify.yaml"
vars="$(plan "$VF")" || exit 1
eval "$vars"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -z "${OUT:-}" ]; then
  if [ -n "${BE_SCRATCH:-}" ]; then OUT="$BE_SCRATCH/verify/$REPO-$STAMP"; else OUT="$ROOT/build/verify/$REPO-$STAMP"; fi
fi
mkdir -p "$OUT"
NET="brickkit-$PROJECT-net"
CP="brickkit-$PROJECT"   # compose 项目名
ROUTE="${ROUTE:-}"
FOCUS="$( [ "${FOCUS:-}" = 1 ] && echo 1 )"; KEEP="$( [ "${KEEP:-}" = 1 ] && echo 1 )"   # 只有 1 算开
IS_GO=0; [ "$IS_SHELL" = 0 ] && [ -f "$ROOT/components/$ID/go.mod" ] && IS_GO=1

ROWS=()
row() { local why="${3//|/¦}"; ROWS+=("$1|$2|$why|${4:-}"); printf '  %-4s %s%s\n' "$2" "$1" "${3:+ — $3}"; }   # 检查项 状态 原因 日志
log() { echo "$OUT/$1"; }
runlog() { local f="$1"; shift; echo "  \$ $*  > $f"; "$@" > "$f" 2>&1; }
curl_in_net() {  # curl_in_net <url> [curl 参数…] → 打印 HTTP 码
  local url="$1"; shift
  docker run --rm --network "$NET" curlimages/curl:latest -s -o /dev/null -w '%{http_code}' --max-time 15 "$@" "$url" 2>/dev/null || true
}
compose_host() {  # compose_host <版本化服务名> → 实际承载它的 compose 服务（外壳托管时是外壳）
  python3 - "$ROOT/.brickkit/generated/compose.yaml" "$1" <<'PY'
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except OSError:
    d = {}
want = sys.argv[2]
for name, s in (d.get("services") or {}).items():
    nets = s.get("networks") or {}
    aliases = [a for v in (nets.values() if isinstance(nets, dict) else []) for a in ((v or {}).get("aliases") or [])]
    if name == want or want in aliases:
        print(name); break
else:
    print(want)
PY
}
container_of() { docker ps -a --filter "label=com.docker.compose.project=$CP" --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' | head -1; }
has() { case " $KEEP_IDS " in *" $1@"*) return 0 ;; esac; return 1; }   # 闭包里有这个组件
project_containers() { docker ps --filter "label=com.docker.compose.project=$CP" --format '{{.Names}}'; }

echo "▶ verify $ID@$VER（项目 $PROJECT；输出 $OUT）"
echo "  闭包：$KEEP_IDS"
[ -n "$DISABLED" ] && echo "  deploy.verify.yaml 里停用：$DISABLED"
cp "$VF" "$OUT/deploy.verify.yaml"
UP_OK=0
FPID=""; FOCUS_STARTED=0; CLEANED=0
stop_focus() {  # 停掉 focus 的整个进程组（setsid 起的，自己一个会话）
  [ -n "$FPID" ] || return 0
  kill -INT -- "-$FPID" 2>/dev/null
  for _ in $(seq 1 20); do kill -0 "$FPID" 2>/dev/null || break; sleep 1; done
  kill -TERM -- "-$FPID" 2>/dev/null; sleep 1; kill -KILL -- "-$FPID" 2>/dev/null; wait "$FPID" 2>/dev/null
  FPID=""
}
# focus 进程跑在宿主机上：config/vars.yaml 里写的 host.docker.internal 在宿主机解析不了（brickKit 只改写它
# 自己算出的 *_ENDPOINT，手写在 config 里的地址原样注入——brickkit docs 10-troubleshooting/02-local-debug-issues
# "The process on this machine can't reach an address written in config"，修法是 deploy.local.yaml 的 vars:）。
# 依赖容器与宿主机进程读的是同一份 vars:，所以不能写 localhost（容器里 localhost 是它自己），而写 Docker 的
# host-gateway 实际映射到的 IP：容器里 host.docker.internal 本来就解析成它，宿主机上它是本机网卡地址。
# 只在 Linux 原生 Docker 上验证过（Docker Desktop / rootless 下 host-gateway 的 IP 宿主机未必可达，那时 focus 大声 FAIL）。
# deploy.local.yaml 的三种起点，收尾（含中断、KEEP=1、local off 失败）一律还原：
#   不存在                → local on 从 deploy.yaml 复制一份；收尾时删掉（否则下一次 focus 会沿用这份副本）
#   存在且本地模式开着    → 是正在用的个人副本：备份后在它上面加 vars:；收尾时原样恢复
#   存在但本地模式关着    → 多半是过期副本（local on 会沿用它而不是重新复制）：移到 $OUT，让 local on 从
#                           deploy.yaml 重新复制；收尾时放回原处
LOCAL_FILE="$ROOT/deploy.local.yaml"; LOCAL_BACKUP=""; LOCAL_CREATED=0; LOCAL_TOUCHED=0
focus_prepare() {  # focus_prepare <验证前 brickkit local status 的第一行>
  LOCAL_TOUCHED=1
  if [ ! -f "$LOCAL_FILE" ]; then
    LOCAL_CREATED=1
  elif [ "$1" = "Local mode: on" ]; then
    LOCAL_BACKUP="$OUT/deploy.local.yaml.before"; cp "$LOCAL_FILE" "$LOCAL_BACKUP"
  else
    LOCAL_BACKUP="$OUT/deploy.local.yaml.stale"; mv "$LOCAL_FILE" "$LOCAL_BACKUP"; LOCAL_CREATED=1
    echo "  本地模式关着却留有 deploy.local.yaml：先移到 $LOCAL_BACKUP，focus 用从 deploy.yaml 新复制的一份，收尾时放回"
  fi
  runlog "$(log local-on.log)" brickkit local on || true
  local gw
  gw="$(docker run --rm --add-host hgw:host-gateway alpine:3.20 getent hosts hgw 2>/dev/null | awk '{print $1}' | head -1)"
  [[ "$gw" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "  （查不到 host-gateway 的 IP，focus 不改写 host.docker.internal）"; return 0; }
  [ -f "$LOCAL_FILE" ] || { echo "  （没有 deploy.local.yaml，focus 不改写 host.docker.internal）"; return 0; }
  [ -f "$ROOT/config/vars.yaml" ] || { echo "  （没有 config/vars.yaml，focus 不改写 host.docker.internal）"; return 0; }
  python3 - "$ROOT/config/vars.yaml" "$LOCAL_FILE" "$gw" <<'PY'
import sys, yaml
vars_file, local_file, gw = sys.argv[1:]
shared = yaml.safe_load(open(vars_file, encoding="utf-8")) or {}
local = yaml.safe_load(open(local_file, encoding="utf-8")) or {}
v = local.get("vars") or {}
changed = [k for k, val in shared.items() if isinstance(val, str) and "host.docker.internal" in val and k not in v]
for k in changed:
    v[k] = shared[k].replace("host.docker.internal", gw)
if changed:
    local["vars"] = v
    with open(local_file, "w", encoding="utf-8") as f:
        f.write("# brickkit local on 的副本；verify-component.sh 为 focus 运行临时加了 vars:（宿主机解析不了 host.docker.internal），收尾时删除或恢复\n")
        yaml.safe_dump(local, f, allow_unicode=True, sort_keys=False)
print("  focus 用 deploy.local.yaml 的 vars: 把 host.docker.internal 换成 host-gateway IP " + gw + "：" + (", ".join(changed) or "（没有要换的）"))
PY
}
focus_restore() {
  [ "$LOCAL_TOUCHED" = 1 ] || return 0
  LOCAL_TOUCHED=0
  if [ -n "$LOCAL_BACKUP" ]; then cp "$LOCAL_BACKUP" "$LOCAL_FILE"; elif [ "$LOCAL_CREATED" = 1 ]; then rm -f "$LOCAL_FILE"; fi
}
on_exit() {  # 正常走完时什么都不做（CLEANED=1）；中断或中途退出时补做收尾
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  trap '' INT TERM  # 收尾期间再来的 INT/TERM 不打断收尾
  stop_focus
  # focus 进程已停：不管 KEEP，本地模式关掉、deploy.local.yaml 还原（KEEP 只保留容器）
  if [ "$FOCUS_STARTED" = 1 ]; then
    echo "▸ 中途退出，收尾：brickkit local off、还原 deploy.local.yaml" >&2
    brickkit local off > "$OUT/local-off-on-exit.log" 2>&1
  fi
  focus_restore
  if [ -z "$KEEP" ]; then
    echo "▸ 中途退出，收尾：brickkit down -f deploy.verify.yaml" >&2
    brickkit down -f "$VF" > "$OUT/down-on-exit.log" 2>&1
    rm -f "$VF"
  fi
}
trap on_exit EXIT
trap 'echo "✗ verify 被中断" >&2; exit 130' INT TERM

# ---------- 1. 构建与镜像检查 ----------
echo; echo "▸ 1. 构建镜像"
if runlog "$(log build.log)" brickkit build "$ID" $( [ "${FORCE_BUILD:-}" = 1 ] && echo --force ); then
  row "brickkit build $ID" PASS "" "$(log build.log)"
else
  row "brickkit build $ID" FAIL "构建失败" "$(log build.log)"
fi
for ref in $KEEP_IDS; do
  [ "$ref" = "$ID@$VER" ] && continue
  c="${ref%@*}"; v="${ref#*@}"
  if [ -z "$(docker image ls -q --filter "label=io.brickkit.component=$c" --filter "label=io.brickkit.version=$v")" ]; then
    f="build-${c//\//-}.log"
    if runlog "$(log "$f")" brickkit build "$ref"; then row "build $ref（闭包里缺镜像）" PASS "" "$(log "$f")"
    else row "build $ref（闭包里缺镜像）" FAIL "构建失败" "$(log "$f")"; fi
  fi
done
IMG="$(docker image ls --filter "label=io.brickkit.component=$ID" --filter "label=io.brickkit.version=$VER" --format '{{.Repository}}:{{.Tag}}' | head -1)"
if [ -z "$IMG" ]; then
  row "镜像检查" FAIL "找不到 label io.brickkit.component=$ID / io.brickkit.version=$VER 的镜像"
else
  if docker run --rm --entrypoint sh "$IMG" -c 'command -v wget >/dev/null && test -f /app/component.yaml' > "$(log image-check.log)" 2>&1; then
    row "镜像 $IMG：sh + wget、/app/component.yaml" PASS "" "$(log image-check.log)"
  else
    row "镜像 $IMG：sh + wget、/app/component.yaml" FAIL "健康检查需要 sh+wget；SDK 从 /app/component.yaml 读端口" "$(log image-check.log)"
  fi
  if [ "$IS_SHELL" = 1 ]; then
    lbl="$(docker image inspect "$IMG" --format '{{ index .Config.Labels "io.brickkit.shell.members" }}')"
    echo "$lbl" > "$(log shell-label.log)"
    miss=""; for m in $MEMBERS; do r="${m%%|*}"; case "$lbl" in *"$r"*) ;; *) miss="$miss $r" ;; esac; done
    if [ -z "$miss" ]; then row "镜像标签 io.brickkit.shell.members 与 shell.members 一致" PASS "$lbl" "$(log shell-label.log)"
    else row "镜像标签 io.brickkit.shell.members 与 shell.members 一致" FAIL "标签缺：$miss" "$(log shell-label.log)"; fi
  fi
fi

# ---------- 2/3. 只起闭包 ----------
echo; echo "▸ 2. 只起闭包（brickkit up -f deploy.verify.yaml）"
if runlog "$(log up.log)" brickkit up -f "$VF"; then
  UP_OK=1; row "brickkit up -f deploy.verify.yaml" PASS "" "$(log up.log)"
else
  row "brickkit up -f deploy.verify.yaml" FAIL "见日志（缺镜像 / 配置 / 迁移失败 / 健康检查超时）" "$(log up.log)"
fi
runlog "$(log status.log)" brickkit status -f "$VF" || true
mig_bad=""; mig_n=0
while IFS=$'\t' read -r name service; do
  [ -n "$name" ] || continue
  mig_n=$((mig_n + 1))
  docker logs "$name" > "$(log "migration-$service.log")" 2>&1
  st="$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$name")"
  [ "$st" = "exited 0" ] || mig_bad="$mig_bad $service($st)"
done < <(docker ps -a --filter "label=com.docker.compose.project=$CP" --format '{{.Names}}	{{.Label "com.docker.compose.service"}}' | awk -F'\t' '$2 ~ /-migration$/')
if [ "$mig_n" = 0 ] && [ "$HAS_MIG" = 1 ]; then row "迁移容器 Exited (0)" FAIL "$ID 声明了 migration，却没找到 *-migration 容器"
elif [ "$mig_n" = 0 ]; then row "迁移容器 Exited (0)" SKIP "闭包里没有迁移容器"
elif [ -z "$mig_bad" ]; then row "迁移容器 Exited (0)（$mig_n 个）" PASS "" "$OUT/migration-*.log"
else row "迁移容器 Exited (0)" FAIL "$mig_bad" "$OUT/migration-*.log"; fi

HOST="$(compose_host "$SVC")"
SC="$(container_of "$HOST")"
hs=""
if [ -n "$SC" ]; then
  for _ in $(seq 1 60); do
    hs="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$SC")"
    [ "$hs" = "running healthy" ] && break
    case "$hs" in exited*|dead*) break ;; esac
    sleep 2
  done
fi
if [ "$hs" = "running healthy" ]; then row "$SVC running (healthy)${HOST:+（容器服务 $HOST）}" PASS "" "$(log status.log)"
else row "$SVC running (healthy)" FAIL "容器 ${SC:-不存在}：${hs:-无}" "$(log status.log)"; fi
[ -n "$SC" ] && docker logs "$SC" > "$(log "container-$HOST.log")" 2>&1

# ---------- 4. 健康与鉴权（组件）/ 运行期核对（外壳） ----------
echo; echo "▸ 3. 健康与鉴权"
if [ "$UP_OK" = 0 ] || [ -z "$SC" ]; then
  row "健康与鉴权检查" SKIP "容器没起来，跳过"
elif [ "$IS_SHELL" = 0 ]; then
  code="$(curl_in_net "http://$SVC:$PORT/healthz")"
  echo "GET http://$SVC:$PORT/healthz → $code" >> "$(log http.log)"
  [ "$code" = 200 ] && row "GET /healthz → 200" PASS "" "$(log http.log)" || row "GET /healthz → 200" FAIL "实际 $code" "$(log http.log)"
  if [ -z "$ROUTE" ]; then
    row "受保护路由" SKIP "没给 ROUTE"
  else
    if [[ "$ROUTE" =~ ^([A-Z]+)[[:space:]]+(.+)$ ]]; then M="${BASH_REMATCH[1]}"; RP="${BASH_REMATCH[2]}"; else M=GET; RP="$ROUTE"; fi
    code="$(curl_in_net "http://$SVC:$PORT$RP" -X "$M")"
    echo "$M http://$SVC:$PORT$RP（不带 token）→ $code" >> "$(log http.log)"
    case "$code" in
      401|503) row "$M $RP 不带 token → 401/503" PASS "实际 $code" "$(log http.log)" ;;
      403) row "$M $RP 不带 token → 401/503" FAIL "实际 403：IAM_JWKS_URL 没注入进去" "$(log http.log)" ;;
      *) row "$M $RP 不带 token → 401/503" FAIL "实际 $code" "$(log http.log)" ;;
    esac
    if has infra/authz && has infra/iam-casdoor; then
        # 只有 Casdoor 明确回答"没有这个用户"（data: null → sub_of 成功但为空）才算种子未灌；其余失败一律 FAIL
        TL="$(log token.log)"
        TOKEN="$( { export ROOT; source "$S/lib/seed-net.sh"; with_toolbox "$NET"
                    sub="$(sub_of dev.superuser)" || { echo "sub_of dev.superuser 失败（Casdoor 不可达或返回不是 JSON）" >&2; exit 5; }
                    [ -n "$sub" ] || exit 4
                    get_app_jwt dev.superuser; } 2> "$TL" )"; trc=$?
        if [ $trc = 4 ]; then
          row "$M $RP 带 token → 200" SKIP "iam 种子还没灌（Casdoor 里没有 dev.superuser；先 make -C components/infra/iam-casdoor seed）"
        elif [ $trc != 0 ] || [ -z "$TOKEN" ]; then
          row "$M $RP 带 token → 200" FAIL "取 dev.superuser 的 token 失败（rc=$trc）" "$TL"
        else
          code="$(curl_in_net "http://$SVC:$PORT$RP" -X "$M" -H "Authorization: Bearer $TOKEN")"
          echo "$M http://$SVC:$PORT$RP（带 dev.superuser 的 token）→ $code" >> "$(log http.log)"
          [ "$code" = 200 ] && row "$M $RP 带 token → 200" PASS "" "$(log http.log)" || row "$M $RP 带 token → 200" FAIL "实际 $code" "$(log http.log)"
        fi
    else
      row "$M $RP 带 token → 200" SKIP "infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token"
    fi
  fi
else
  # 外壳：component-loop §4.5 的运行期核对（只看生成文件不算数）
  served="$(docker exec "$SC" sh -c 'printf %s "$BRICKKIT_SERVED_MEMBERS"' 2>&1)"
  echo "$served" > "$(log served-members.log)"
  miss=""; for m in $MEMBERS; do s="$(echo "$m" | cut -d'|' -f2)"; case "$served" in *"$s"*) ;; *) miss="$miss $s" ;; esac; done
  [ -z "$miss" ] && row "BRICKKIT_SERVED_MEMBERS 含全部成员" PASS "$served" "$(log served-members.log)" \
                 || row "BRICKKIT_SERVED_MEMBERS 含全部成员" FAIL "缺：$miss" "$(log served-members.log)"
  docker exec "$SC" sh -c 'printf %s "$BRICKKIT_SERVED_MEMBERS_CONFIG"' > "$(log served-members-config.json)" 2>&1
  if python3 - "$(log served-members-config.json)" $(for m in $MEMBERS; do printf '%s ' "${m%%|*}"; done) > "$(log served-members-config.log)" 2>&1 <<'PY'
import json, sys
ms = json.load(open(sys.argv[1], encoding="utf-8"))
want, got = set(sys.argv[2:]), set()
for m in ms:
    cid, ver, cfg = m.get("componentId"), m.get("version"), m.get("config")
    print(cid, ver, m.get("httpPort"), sorted(cfg or {}))
    assert isinstance(cfg, dict) and cfg, f"{cid} 的 config 为空"
    got.add(f"{cid}@{ver}")
assert want <= got, f"JSON 里缺成员：{sorted(want - got)}"
PY
  then
    row "BRICKKIT_SERVED_MEMBERS_CONFIG 是合法 JSON、每个成员有自己的 config" PASS "" "$(log served-members-config.log)"
  else
    row "BRICKKIT_SERVED_MEMBERS_CONFIG 是合法 JSON、每个成员有自己的 config" FAIL "见日志" "$(log served-members-config.log)"
  fi
  docker logs "$SC" > "$(log shell.log)" 2>&1
  e1="$(grep -iE '"level": ?"error"' "$(log shell.log)" | head -5)"
  e2="$(grep -E 'module_component_id' "$(log shell.log)" | grep -iE 'error|panic' | head -5)"
  rs="$(docker inspect -f '{{.RestartCount}} {{.State.Status}}' "$SC")"
  [ -z "$e1" ] && row "R15：外壳日志没有 error 级别" PASS "" "$(log shell.log)" || row "R15：外壳日志没有 error 级别" FAIL "$(echo "$e1" | head -1)" "$(log shell.log)"
  [ -z "$e2" ] && row "R15：没有带 module_component_id 的 error/panic" PASS "" "$(log shell.log)" || row "R15：没有带 module_component_id 的 error/panic" FAIL "$(echo "$e2" | head -1)" "$(log shell.log)"
  [ "$rs" = "0 running" ] && row "R15：RestartCount/状态 = 0 running" PASS "" || row "R15：RestartCount/状态 = 0 running" FAIL "实际 $rs"
  code="$(curl_in_net "http://$SVC:$PORT/healthz")"
  echo "GET http://$SVC:$PORT/healthz → $code" >> "$(log http.log)"
  [ "$code" = 200 ] && row "外壳 /healthz → 200" PASS "" "$(log http.log)" || row "外壳 /healthz → 200" FAIL "实际 $code" "$(log http.log)"
  for m in $MEMBERS; do
    ms="$(echo "$m" | cut -d'|' -f2)"; mp="$(echo "$m" | cut -d'|' -f3)"
    code="$(curl_in_net "http://$ms:$mp/healthz")"
    echo "GET http://$ms:$mp/healthz → $code" >> "$(log http.log)"
    [ "$code" = 200 ] && row "成员 $ms /healthz（按自己的服务名）→ 200" PASS "" "$(log http.log)" \
                      || row "成员 $ms /healthz（按自己的服务名）→ 200" FAIL "实际 $code" "$(log http.log)"
  done
  row "成员受保护路由带 token → 200" SKIP "外壳分支只查 /healthz 与运行期核对；每个成员经外壳带真 token 打受保护路由由全栈集成（06b T25）覆盖"
fi

# ---------- 5. 跨组件测试 ----------
echo; echo "▸ 4. 跨组件测试"
if [ "$IS_GO" = 0 ]; then
  row "make test-cross ID=$ID" SKIP "$( [ "$IS_SHELL" = 1 ] && echo '外壳：对每个成员单独跑 make test-cross' || echo '不是 Go 组件（test-cross 只跑 Go）')"
elif [ "$UP_OK" = 0 ]; then
  row "make test-cross ID=$ID" SKIP "容器没起来，跳过"
elif runlog "$(log test-cross.log)" make --no-print-directory -C "$ROOT" test-cross ID="$ID"; then
  row "make test-cross ID=$ID" PASS "" "$(log test-cross.log)"
else
  row "make test-cross ID=$ID" FAIL "见日志" "$(log test-cross.log)"
fi

# ---------- 6. focus ----------
echo; echo "▸ 5. focus 运行"
if [ -z "$FOCUS" ]; then
  row "brickkit up --focus $ID" SKIP "没设 FOCUS=1"
else
  was_local="$(brickkit local status 2>&1 | head -1)"
  FOCUS_STARTED=1
  focus_prepare "$was_local"
  # 非交互 shell 的后台进程默认忽略 SIGINT：恢复默认处理，Ctrl+C 等价的 INT 才能让 brickkit 正常停掉本地进程
  env --default-signal=INT,TERM setsid brickkit up --focus "$ID" > "$(log focus.log)" 2>&1 < /dev/null &
  FPID=$!
  hp="$PORT"; code=""; ok=0
  for _ in $(seq 1 120); do
    p="$(grep -oE "$SVC +listening on port [0-9]+" "$(log focus.log)" | grep -oE '[0-9]+$' | tail -1)"
    [ -n "$p" ] && hp="$p"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://localhost:$hp/healthz" 2>/dev/null || true)"
    [ "$code" = 200 ] && { ok=1; break; }
    kill -0 "$FPID" 2>/dev/null || break
    sleep 1
  done
  [ "$ok" = 1 ] && row "focus：宿主机 http://localhost:$hp/healthz → 200" PASS "" "$(log focus.log)" \
                || row "focus：宿主机 http://localhost:$hp/healthz → 200" FAIL "实际 ${code:-无}$(kill -0 "$FPID" 2>/dev/null || echo '；focus 进程已退出')" "$(log focus.log)"
  stop_focus
  runlog "$(log focus-all-dry-run.log)" brickkit up --all --dry-run \
    && row "brickkit up --all --dry-run（清除 focus）" PASS "" "$(log focus-all-dry-run.log)" \
    || row "brickkit up --all --dry-run（清除 focus）" FAIL "见日志" "$(log focus-all-dry-run.log)"
  runlog "$(log local-status.log)" brickkit local status || true
  if runlog "$(log local-off.log)" brickkit local off; then
    row "brickkit local off" PASS "$( [ "$was_local" = "Local mode: on" ] && echo "验证前本地模式是开的，已关闭；需要时 brickkit local on")" "$(log local-off.log)"
  else
    row "brickkit local off" FAIL "见日志" "$(log local-off.log)"
  fi
  FOCUS_STARTED=0
  focus_restore   # local off 成败都还原 deploy.local.yaml
fi

# ---------- 7. 收尾 ----------
echo; echo "▸ 6. 收尾"
CLEANED=1   # 从这里起由正常路径收尾，EXIT 陷阱不再重复
if [ -n "$KEEP" ]; then
  row "brickkit down" SKIP "KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml"
else
  runlog "$(log down.log)" brickkit down -f "$VF" || true
  if [ -n "$(project_containers)" ]; then runlog "$(log down-2.log)" brickkit down || true; fi
  left="$(project_containers | tr '\n' ' ')"
  [ -z "$left" ] && row "brickkit down：docker ps 里没有本项目（$CP）的容器" PASS "" "$(log down.log)" \
                 || row "brickkit down：docker ps 里没有本项目（$CP）的容器" FAIL "还在跑：$left" "$(log down.log)"
  # 副本已在输出目录；项目根不留它（brickkit 会把它当成又一个部署文件，upgrade 时提示"没同步"）
  [ -z "$left" ] && rm -f "$VF"
fi

# ---------- 汇总 ----------
{
  echo
  echo "verify $ID@$VER 汇总（输出目录 $OUT）"
  printf '| %s | %s | %s | %s |\n' 检查项 结果 原因 日志
  printf '|---|---|---|---|\n'
  for r in "${ROWS[@]}"; do IFS='|' read -r a b c d <<< "$r"; printf '| %s | %s | %s | %s |\n' "$a" "$b" "$c" "${d#"$OUT"/}"; done
} | tee "$OUT/summary.md"
if printf '%s\n' "${ROWS[@]}" | cut -d'|' -f2 | grep -qx FAIL; then
  echo "✗ 有 FAIL（汇总：$OUT/summary.md）"; exit 1
fi
echo "✓ 全部 PASS 或写明原因的 SKIP（汇总：$OUT/summary.md）"
