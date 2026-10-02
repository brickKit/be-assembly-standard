#!/usr/bin/env bash
# 第 4.0–4.4 步与 4.6（SDK ≥ v0.4.0 时改迁移入口，见 migrate-entry.py）：Go 组件的模块路径改 /v2、契约包统一成嵌套模块、根 go.mod require 真实的契约包版本、升 SDK，
# 最后跑 component-loop 4.4 的全部判据（每条打印 PASS/FAIL，有 FAIL 就 exit 1）。
#
# 用法：bash dev/phase-06/tools/go-v2.sh <scope>/<name> --sdk <be-sdk-go tag>
#       bash dev/phase-06/tools/go-v2.sh <scope>/<name> --recheck [--sdk <tag>]
#   BE_SCRATCH 必填（见 env.sh）；BE_COMP_DIR 可改组件目录。
# 步骤（每步都先看是否已经做过，做过就跳过，所以可以重复运行）：
#   4.0 判形态：gen/<domain>/<name>/go.mod 在 → 形态 A（或已拆过的 B）；不在 → 形态 B
#   4.1 形态 B：拆出嵌套模块（go mod init + 与根模块同版本的 grpc/protobuf + tidy + build），根 go.mod 加 require + replace；
#       Dockerfile 改成先 `COPY . .` 再 `go mod download`（本地 replace 要求目录在场）
#   C-1 残留：根 go.mod 里 require 了自己的旧路径（github.com/brickKit/<repo> v1.x.y）→ 删掉并大声报出来
#   4.2 go mod edit -module …/v2；改写全部自引用 import（契约包 …/<repo>/gen/… 不改）
#   4.3 契约包版本：本地 gen/ 与最新 gen/* tag 一致 → require 那个 tag；不一致 → 下一个 minor；没有 tag（形态 B）→ v1.0.0
#   4.4 go get be-sdk-go@<tag>、go mod tidy、go build ./...、go vet ./...，然后跑判据
# --recheck：契约改动（改 .proto → buf generate）之后用，只重算 4.3 并重跑 tidy/build/vet 与判据（不拆、不改 import、不升 SDK、
#   不清 C-1 残留——让判据把它报出来）；最后打印第 8.3 步需要打的契约包 tag（或"不需要"）。
# 判据还核对 gen/ 是不是当前 .proto 的生成结果（buf generate 到 $S 下的临时目录比对，不写 gen/）。
# 退出码：0 全部 PASS；1 有判据 FAIL；2 用法错误或某一步执行失败。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
die() { echo "❌ go-v2.sh: $*" >&2; exit 2; }
step() { echo; echo "▶ $*"; }
did() { echo "  ✏️  $*"; }
skip() { echo "  ⏭  $*"; }
run() { echo "  \$ $*"; "$@" || die "命令失败：$*"; }

ID=""; SDK=""; RECHECK=0
while [ $# -gt 0 ]; do
  case $1 in
    --sdk) SDK=${2:-}; [ -n "$SDK" ] || die "--sdk 后面要跟 be-sdk-go 的 tag"; shift 2 ;;
    --recheck) RECHECK=1; shift ;;
    -*) die "不认识的参数 $1" ;;
    *) [ -z "$ID" ] && ID=$1 || die "多余的参数 $1"; shift ;;
  esac
done
[ -n "$ID" ] || die "用法：bash go-v2.sh <scope>/<name> --sdk <tag> | --recheck"
[ $RECHECK = 1 ] || [ -n "$SDK" ] || die "要么给 --sdk <tag>（完整迁移），要么给 --recheck（契约改动后重算）"
envout=$(bash "$HERE/env.sh" "$ID") || exit 2
eval "$envout"
cd "$C" || die "进不了 $C"
[ -f go.mod ] || die "$ID 不是 Go 组件（$C 下没有 go.mod）"
command -v go >/dev/null || die "PATH 里没有 go"

M=github.com/brickKit/$REPO
MQ=$(printf '%s' "$M" | sed 's/[.]/\\./g')          # 给正则用
GD=$(ls -d gen/*/*/ 2>/dev/null | grep -v '__pycache__' || true)
[ -n "$GD" ] || die "$C 下没有 gen/<domain>/<name>/ 契约包目录"
[ "$(printf '%s\n' "$GD" | wc -l)" = 1 ] || die "gen/ 下有不止一个契约包目录，脚本不知道选哪个：$(echo $GD)"
G=${GD%/}; GREL=${G#gen/}; GM=$M/$G
gomod_hash() { sha1sum go.mod "$G/go.mod" 2>/dev/null | sha1sum; }

echo "🔧 $ID：Go /v2 迁移（$C）$([ $RECHECK = 1 ] && echo '— 只重算 4.3 + 判据')"
echo "   模块 $M → $M/v2；契约包 $GM（目录 $G，不带 /v2）"

# ── 4.0 形态 ──
step "4.0 判形态"
LAST_TAG=$(git tag -l "gen/$GREL/v*" | sort -V | tail -1)
if [ -f "$G/go.mod" ]; then
  if [ -n "$LAST_TAG" ]; then echo "  形态 A（嵌套模块；最新契约包 tag $LAST_TAG）"
  else echo "  形态 B，已拆成嵌套模块（还没有契约包 tag）"; fi
else
  echo "  形态 B（gen/ 属于根模块；$G/go.mod 不存在，没有 gen/* tag）"
fi

if [ $RECHECK = 0 ]; then
  # ── 4.1 形态 B 拆嵌套模块 ──
  step "4.1 契约包拆成嵌套模块（只有形态 B）"
  if [ -f "$G/go.mod" ]; then
    skip "$G/go.mod 已存在"
  else
    VG=$(go list -m -f '{{.Version}}' google.golang.org/grpc 2>/dev/null) || die "根模块没有 google.golang.org/grpc（go list -m 失败）"
    VP=$(go list -m -f '{{.Version}}' google.golang.org/protobuf 2>/dev/null) || die "根模块没有 google.golang.org/protobuf"
    GOV=$(awk '$1=="go"{print $2; exit}' go.mod)
    ( cd "$G" && run go mod init "$GM" && run go mod edit -go="$GOV" -require=google.golang.org/grpc@"$VG" -require=google.golang.org/protobuf@"$VP" \
      && run go mod tidy && run go build ./... ) || die "拆契约包模块失败"
    did "新建 $G/go.mod（grpc $VG、protobuf $VP，与根模块同版本）"
    run go mod edit -require="$GM"@v1.0.0 -replace="$GM"=./"$G"
    did "根 go.mod：require $GM v1.0.0 + replace => ./$G"
  fi
  # Dockerfile：本地 replace 下 `COPY go.mod go.sum ./` + `go mod download` 会失败，改成先 COPY . .
  if [ -f Dockerfile ]; then
    python3 - Dockerfile <<'EOF' || die "改 Dockerfile 失败"
import re, sys
p = sys.argv[1]; lines = open(p, encoding='utf-8').read().split('\n')
cg = next((i for i, l in enumerate(lines) if re.match(r'^COPY\s+go\.mod(\s+go\.sum)?\s+\./?\s*$', l)), None)
dl = next((i for i, l in enumerate(lines) if re.match(r'^RUN\s+go mod download\s*$', l)), None)
ca = next((i for i, l in enumerate(lines) if re.match(r'^COPY\s+\.\s+\.\s*$', l)), None)
if cg is not None and dl is not None and cg < dl and (ca is None or ca > dl):
    if ca is not None:
        del lines[ca]
    lines[cg] = 'COPY . .'
    open(p, 'w', encoding='utf-8').write('\n'.join(lines))
    print('  ✏️  Dockerfile：`COPY go.mod go.sum ./` + `go mod download` 改成先 `COPY . .` 再 `go mod download`')
else:
    print('  ⏭  Dockerfile 不需要改（没有先拷 go.mod 再 download 的写法）')
EOF
  fi

  # ── C-1 残留 ──
  step "C-1 检查：根 go.mod 是否 require 了自己的旧路径"
  if grep -qE "^[[:space:]]*(require[[:space:]]+)?$MQ[[:space:]]+v" go.mod; then
    echo "  ⚠️  发现 C-1 残留：$(grep -nE "^[[:space:]]*(require[[:space:]]+)?$MQ[[:space:]]+v" go.mod | head -1)"
    echo "     （形态 B 被当成形态 A 改过：go mod tidy 把自己上一个已发布版本加了回来，v2 在对着 v1 的生成代码编译）"
    run go mod edit -droprequire="$M"
    did "删掉 require $M"
  else
    skip "没有"
  fi

  # ── 4.2 /v2 ──
  step "4.2 模块路径改 /v2，改写自引用 import"
  if [ "$(head -1 go.mod)" = "module $M/v2" ]; then skip "go.mod 已是 module $M/v2"
  else run go mod edit -module "$M/v2"; did "go.mod：module $M/v2"; fi
  files=$(git ls-files -co --exclude-standard -- '*.go' | grep -v '^gen/' | xargs -r grep -lP "\"\\Q$M\\E/(?!v2/|gen/)" 2>/dev/null || true)
  if [ -z "$files" ]; then skip "import 已全部带 /v2（契约包除外）"
  else
    for f in $files; do
      n=$(grep -cP "\"\\Q$M\\E/(?!v2/|gen/)" "$f")
      perl -pi -e 's#"\Q'"$M"'\E/(?!v2/|gen/)#"'"$M"'/v2/#g' "$f" || die "改写 $f 失败"
      did "$f：$n 行 import 改成 $M/v2/…"
    done
  fi
  others=$(git ls-files -co --exclude-standard | grep -v -e '\.go$' -e '^gen/' -e '^go\.\(mod\|sum\)$' | xargs -r grep -lP "\\Q$M\\E(?!/v2|/gen/|-)" 2>/dev/null || true)
  [ -n "$others" ] && echo "  ℹ️  这些非 Go 文件还提到 $M（不带 /v2），按 component-loop 4.7 人工核对：$(echo $others)"
fi

# ── 4.3 契约包版本 ──
step "4.3 根 go.mod require 的契约包版本"
GV=""; NEED_TAG=""
if [ ! -f "$G/go.mod" ]; then
  echo "  ⚠️  $G/go.mod 不存在：契约包不是嵌套模块，没法确定版本（先跑不带 --recheck 的 go-v2.sh）"
else
  if [ -z "$LAST_TAG" ]; then
    GV=v1.0.0; NEED_TAG=gen/$GREL/$GV; echo "  没有 gen/$GREL/v* tag（形态 B 拆出来）→ $GV"
  elif git diff --quiet "$LAST_TAG" -- "$G" && [ -z "$(git ls-files -o --exclude-standard -- "$G")" ]; then
    GV=${LAST_TAG##*/}; echo "  本地 $G 与 $LAST_TAG 一致 → $GV"
  else
    lv=${LAST_TAG##*/v}; IFS=. read -r ma mi _ <<<"$lv"
    GV=v$ma.$((mi + 1)).0; NEED_TAG=gen/$GREL/$GV
    echo "  本地 $G 与 $LAST_TAG 不一致（契约有变化）→ 下一个 minor $GV"
    git diff --stat "$LAST_TAG" -- "$G" | sed 's/^/     /'
  fi
  before=$(gomod_hash)
  run go mod edit -require="$GM@$GV" -replace="$GM"=./"$G"
  [ "$before" = "$(gomod_hash)" ] && skip "go.mod 已是 require $GM $GV + replace" || did "go.mod：require $GM $GV（本地 replace => ./$G）"
fi

# ── 4.4 SDK、整理、编译 ──
step "4.4 升 SDK、tidy、build、vet"
BUILD=PASS
if [ $RECHECK = 0 ] && [ -n "$SDK" ]; then
  cur=$(go list -m -f '{{.Version}}' github.com/brickKit/be-sdk-go 2>/dev/null || true)
  if [ "$cur" = "$SDK" ]; then skip "be-sdk-go 已是 $SDK"
  else
    echo "  \$ go get github.com/brickKit/be-sdk-go@$SDK"
    go get "github.com/brickKit/be-sdk-go@$SDK" >"$S/go-get.log" 2>&1; rc=$?; cat "$S/go-get.log"
    if [ $rc != 0 ]; then
      if grep -q 'sum.golang.org.*404\|unknown revision' "$S/go-get.log"; then
        echo "  ℹ️  tag 刚推送时，proxy.golang.org / sum.golang.org 会把之前查不到的结果缓存一阵子（负缓存）。" >&2
        echo "     确认远端有这个 tag（git -C \$ROOT/tools/be-sdk-go ls-remote --tags origin $SDK）后，可临时 GONOSUMDB=github.com/brickKit 重跑（回落到 git 直取，go.sum 照常记录）。" >&2
      fi
      die "go get be-sdk-go@$SDK 失败（此时 4.1–4.3 已经做完，修好后原样重跑即可）"
    fi
    did "be-sdk-go $cur → $SDK"
  fi
fi
# be-sdk-go v0.4.0 起删了 Module.Migrations：迁移只由 brickKit 用组件镜像跑 backend/cmd/migrate（component-loop §4.6）
SDKV=${SDK:-$(go list -m -f '{{.Version}}' github.com/brickKit/be-sdk-go 2>/dev/null || true)}
sdk_ge_04() { python3 -c "import re,sys; m=re.match(r'v(\d+)\.(\d+)\.(\d+)', sys.argv[1]); sys.exit(0 if m and tuple(map(int,m.groups()))>=(0,4,0) else 1)" "$1"; }
NEW_MIGRATE=0; sdk_ge_04 "$SDKV" && NEW_MIGRATE=1
if [ $RECHECK = 0 ]; then
  step "4.6 迁移入口改成 SDK 的一行（be-sdk-go ≥ v0.4.0）"
  if [ $NEW_MIGRATE = 1 ]; then
    python3 "$HERE/migrate-entry.py" "$C" --apply || die "改迁移入口失败"
  else
    skip "be-sdk-go 是 ${SDKV:-?}（< v0.4.0），Module.Migrations 还在，不改"
  fi
fi
before=$(gomod_hash)
for cmd in "go mod tidy" "go build ./..." "go vet ./..."; do
  echo "  \$ $cmd"
  if ! $cmd; then BUILD=FAIL; echo "  ❌ $cmd 失败"; break; fi
done
[ "$before" = "$(gomod_hash)" ] || did "go mod tidy 改了 go.mod / go.sum"

# ── 判据（component-loop 4.4） ──
step "判据"
NFAIL=0
crit() {  # crit <PASS|FAIL> <说明>
  if [ "$1" = PASS ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; NFAIL=$((NFAIL + 1)); fi
}
pf() { if "$@"; then echo PASS; else echo FAIL; fi; }

crit $BUILD "go mod tidy + go build ./... + go vet ./... 通过（BUILD_OK）"
# gen/ 是否由当前 .proto 生成（task-7 审查 Minor 8）：改了 .proto 忘了 buf generate、或手改了 *.pb.go，4.3 会把旧 gen
# 当成"与上一个 tag 一致"，所有判据照绿。buf generate 写到 $S 下的临时目录（不碰 gen/），与 gen/ 的 *.pb.go 逐个比；
# 本项目的 buf.gen.yaml 只用本机插件（local: protoc-gen-go / protoc-gen-go-grpc）、buf.yaml 没有 deps，离线可跑。
gen_probs() {
  [ -f buf.gen.yaml ] || { echo "没有 buf.gen.yaml，无法核对"; return; }
  command -v buf >/dev/null || { echo "PATH 上没有 buf（env.sh 会把 \$HOME/go/bin 追加进 PATH）"; return; }
  local tmp; tmp=$(mktemp -d "$S/gen-check.XXXXXX") || { echo "建不了临时目录"; return; }
  if ! buf generate --template buf.gen.yaml -o "$tmp" >"$tmp/buf.log" 2>&1; then
    echo "buf generate 失败：$(head -3 "$tmp/buf.log" | tr '\n' ' ')"
  else
    # 比对脚本自己出错（读不了生成物、解码失败）也是问题：退出码非零就记一条，stderr 一并收进 gprob（审查 Minor 1）
    python3 - gen "$tmp/gen" <<'PYEOF' || echo "gen/ 比对脚本出错（exit $?），无法确认 gen/ 是最新的"
import os, sys
a, b = sys.argv[1:3]
def pbs(root):
    return {os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs if f.endswith('.pb.go')} \
        if os.path.isdir(root) else set()
ga, gb = pbs(a), pbs(b)
for p in sorted(ga - gb):
    print(f'gen/{p}：在 gen/ 里，但当前 .proto 生成不出它（删掉的 .proto 留下的，或手工加的）')
for p in sorted(gb - ga):
    print(f'gen/{p}：当前 .proto 会生成它，但 gen/ 里没有（忘了 buf generate）')
for p in sorted(ga & gb):
    if open(os.path.join(a, p), 'rb').read() != open(os.path.join(b, p), 'rb').read():
        print(f'gen/{p}：内容与 buf generate 的结果不同（改了 .proto 没重新生成，或手改了生成物）')
PYEOF
  fi
  rm -rf "$tmp"
}
gprob=$(gen_probs 2>&1)
crit "$(pf test -z "$gprob")" "gen/ 是当前 contracts/*.proto 的生成结果（buf generate 到临时目录比对）"
[ -n "$gprob" ] && echo "$gprob" | head -10 | sed 's/^/        │ /'
crit "$(pf test "$(head -1 go.mod)" = "module $M/v2")" "go.mod 第一行是 module $M/v2（实际：$(head -1 go.mod)）"
old=$(grep -nE "^[[:space:]]*(require[[:space:]]+)?$MQ[[:space:]]+v" go.mod || true)
crit "$(pf test -z "$old")" "go.mod 没有 require 自己的旧路径 $M v1.x.y${old:+（实际：$old）}"
crit "$(pf test -f "$G/go.mod")" "契约包是嵌套模块（$G/go.mod 存在）"
if [ -f "$G/go.mod" ]; then
  crit "$(pf test "$(head -1 "$G/go.mod")" = "module $GM")" "契约包模块路径是 $GM，不带 /v2（实际：$(head -1 "$G/go.mod")）"
fi
req=$(go mod edit -json 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
r=[x['Version'] for x in d.get('Require') or [] if x['Path']=='$GM']
p=[x['New']['Path'] for x in d.get('Replace') or [] if x['Old']['Path']=='$GM' and not x['Old'].get('Version')]
print((r[0] if r else '-')+' '+(p[0] if p else '-'))")
crit "$(pf test "$req" = "${GV:-?} ./$G")" "根 go.mod require $GM ${GV:-?}（不是 v0.0.0）+ replace => ./$G（实际：$req）"
# 契约包之外的 replace（例如为了先用上未发布的 SDK 指到本机 tools/be-sdk-go）：本机全绿，brickkit build 时路径不在构建上下文里才失败
stray=$(go mod edit -json 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
print(' '.join(x['Old']['Path']+'=>'+x['New']['Path'] for x in d.get('Replace') or [] if x['Old']['Path']!='$GM'))")
crit "$(pf test -z "$stray")" "根 go.mod 里除契约包外没有别的 replace${stray:+（多出：$stray）}"

mods=$(go list -m all 2>/dev/null | awk -v m="$M" '$1==m || index($1, m"/")==1' | sort)
want=$(printf '%s\n%s\n' "$M/v2" "$GM ${GV:-?} => ./$G" | sort)
crit "$(pf test "$mods" = "$want")" "go list -m all 里本仓库模块恰好两行：$M/v2 与 $GM ${GV:-?} => ./$G"
echo "$mods" | sed 's/^/        │ /'
deps=$(go list -deps -test -f '{{if .Module}}{{.Module.Path}}{{end}}' ./... 2>/dev/null | sort -u | awk -v m="$M" '$1==m || index($1, m"/")==1')
extra=$(echo "$deps" | grep -vxF -e "$M/v2" -e "$GM" | grep -v '^$' || true)
crit "$(pf test -z "$extra" -a -n "$(echo "$deps" | grep -xF "$M/v2")")" "go list -deps 里的本仓库模块只有 $M/v2 与 $GM${extra:+（多出：$(echo $extra)）}"
# 含不带子路径的裸导入 "$M"（旧根包）；也查 //go:build ignore 之类不参与编译的文件
bad_imp=$(grep -rnE --include='*.go' "\"$MQ(/|\")" . | grep -vE -e "\"$MQ/v2/" -e "\"$MQ/gen/" || true)
bad_gen=$(grep -rnE --include='*.go' "\"$MQ/v2/gen/" . || true)
crit "$(pf test -z "$bad_imp$bad_gen")" "import 全部带 /v2（契约包 $M/gen/… 除外；没有裸导入 \"$M\"，也没有 $M/v2/gen/…）"
[ -n "$bad_imp$bad_gen" ] && printf '%s\n%s\n' "$bad_imp" "$bad_gen" | grep -v '^$' | head -10 | sed 's/^/        │ /'
if [ -f Dockerfile ]; then
  crit "$(pf awk '/^RUN.*go mod download/{if(!d)d=NR} /^COPY[ \t]+\.[ \t]+\./{if(!c)c=NR} END{exit !(d==0 || (c && c<d))}' Dockerfile)" \
    "Dockerfile 先 COPY . . 再 go mod download（本地 replace 要求契约包目录在场）"
fi
if [ $NEW_MIGRATE = 1 ]; then
  mprob=$(python3 "$HERE/migrate-entry.py" "$C" --check 2>&1)
  crit "$(pf test -z "$mprob")" "backend/cmd/migrate/main.go 恰好是 migrate.Main(migrations.FS) 一行入口，代码里没有 Migrations 字段（be-sdk-go ≥ v0.4.0）"
  [ -n "$mprob" ] && echo "$mprob" | sed 's/^/        │ /'
fi
if [ -f Dockerfile ]; then
  # 迁移镜像：brickKit 用组件镜像跑 migration.command（./migrate up），二进制必须编进镜像
  mout=$(grep -oE -- '-o[[:space:]]+[^[:space:]]+[[:space:]]+\./backend/cmd/migrate' Dockerfile | awk '{print $2}' | head -1)
  crit "$(pf test -n "$mout" -a -n "$(grep -E "^COPY[[:space:]]+--from=[^[:space:]]+[[:space:]]+$mout([[:space:]]|$)" Dockerfile 2>/dev/null)")" \
    "Dockerfile 编译 ./backend/cmd/migrate 并把二进制拷进最终镜像${mout:+（$mout）}"
fi
if [ -n "$SDK" ]; then
  sv=$(go list -m -f '{{.Version}}' github.com/brickKit/be-sdk-go 2>/dev/null || echo '?')
  crit "$(pf test "$sv" = "$SDK")" "be-sdk-go 是 $SDK（实际：$sv）"
fi

echo
if [ -n "$NEED_TAG" ]; then
  echo "📌 第 8.3 步需要打的契约包 tag：$NEED_TAG（必须等于根 go.mod require 的版本；推送前外壳拉不到）"
elif [ -n "$GV" ]; then
  echo "📌 第 8.3 步：不需要打契约包 tag（本地 $G 与 $LAST_TAG 一致）"
else
  echo "📌 第 8.3 步：无法判断（契约包还不是嵌套模块）"
fi
if [ $NFAIL -gt 0 ]; then echo "❌ go-v2.sh：$NFAIL 条判据 FAIL" >&2; exit 1; fi
echo "✅ go-v2.sh：判据全部 PASS"
