#!/usr/bin/env bash
# ship.sh 的测试：在临时目录的 bare 仓库 + clone 上跑，绝不碰真实远端。
#   dry-run：步骤顺序、只打印改动类命令、N-3（已发布契约包与 HEAD 不一致）能抓到、各种前置失败即停。
#   真跑（远端是本地 bare 仓库，brickkit 是 PATH 上的假程序）：tag 指向 HEAD、可重跑、不移动已推送的 tag。
# 用法：bash infra/scripts/tests/test_ship_dryrun.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SHIP="$ROOT/infra/scripts/ship.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  ok   $1"; }
bad() { printf "  FAIL %b\n" "$1" >&2; fail=1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export SHIP_PROBE_INTERVAL=0 SHIP_PROBE_RETRIES=1 GOPROXY=off GOFLAGS=-mod=mod

# 假 brickkit：记录调用；release 按 component.yaml 的版本打注解 tag 并推送（brickkit 的真实行为）
mkdir -p "$T/bin"
cat > "$T/bin/brickkit" <<'EOF'
#!/usr/bin/env bash
# version 不记进调用日志（版本核对每次都跑；FAKE_BK_VERSION 模拟 PATH 上是别的版本）
[ "$1" = version ] && { echo "BrickKit CLI ${FAKE_BK_VERSION:-v1.1.0}"; echo "Supported deploy targets: docker"; exit 0; }
echo "brickkit $*" >> "$FAKE_CALLS"
if [ "$1" = release ]; then
  ver="$(awk '/^  version:/{print $2; exit}' component.yaml)"
  notes="$3"
  git tag -a "$ver" -F "$notes" && git push -q origin "$ver" || { git tag -d "$ver" >/dev/null 2>&1; exit 1; }
fi
EOF
chmod +x "$T/bin/brickkit"
export PATH="$T/bin:$PATH" FAKE_CALLS="$T/calls"
: > "$FAKE_CALLS"
printf '## 新增\n- 测试发布\n' > "$T/notes.md"

# 玩具父仓库：tools/be-acceptance 是本仓库 be-acceptance 当前提交的 clone，父仓库按 gitlink 钉住它
# （ship 只用钉住的、干净的门禁；见 I-3）。ship 以 BE_ROOT 为本仓库根。
P="$T/proj"; ACC="$P/tools/be-acceptance"
git init -q -b main "$P"
git clone -q "$ROOT/tools/be-acceptance" "$ACC" 2>/dev/null || { echo "clone be-acceptance 失败" >&2; exit 1; }
pin_acc() { git -C "$P" -c advice.addEmbeddedRepo=false add tools/be-acceptance && git -C "$P" commit -q -m "pin be-acceptance" --allow-empty; }
pin_acc
export BE_ROOT="$P"

# fixture <名字> <go|python|shell>：建 bare 远端 + clone，提交并推送 main，回显工作目录。
# 工作目录放在 $T/<名字>/components/demo/thing（外壳：shell/be/x）：ship 的发布前门禁以组件目录往上三层为项目根
fixture() {
  local name="$1" kind="$2" w="$T/$1/components/demo/thing" r="$T/$1/remote.git"
  [ "$kind" = shell ] && w="$T/$1/shell/be/x"
  git init -q --bare -b main "$r"
  git clone -q "$r" "$w" 2>/dev/null
  git -C "$w" checkout -q -b main 2>/dev/null || true
  if [ "$kind" = shell ]; then
    printf 'apiVersion: brickkit/v1\nkind: Component\nmetadata:\n  id: be/x\n  version: 1.0.0\nshell:\n  members: [demo/thing@2.0.0]\n' > "$w/component.yaml"
    printf 'module github.com/brickKit/be-x\n\ngo 1.25.0\n' > "$w/go.mod"
  else
    printf 'apiVersion: brickkit/v1\nkind: Component\nmetadata:\n  id: demo/thing\n  version: 2.0.0\n' > "$w/component.yaml"
  fi
  if [ "$kind" = go ]; then
    mkdir -p "$w/gen/demo/thing" "$w/backend/module"
    printf 'module github.com/brickKit/demo-thing/v2\n\ngo 1.25.0\n\nrequire github.com/brickKit/demo-thing/gen/demo/thing v1.0.0\n\nreplace github.com/brickKit/demo-thing/gen/demo/thing => ./gen/demo/thing\n' > "$w/go.mod"
    printf 'module github.com/brickKit/demo-thing/gen/demo/thing\n\ngo 1.25.0\n' > "$w/gen/demo/thing/go.mod"
    printf 'package thing\n\nconst V = 1\n' > "$w/gen/demo/thing/thing.go"
    printf 'package module\n' > "$w/backend/module/module.go"
  fi
  if [ "$kind" = python ]; then printf '[project]\nname = "x"\n' > "$w/pyproject.toml"; fi
  git -C "$w" add -A && git -C "$w" commit -q -m init && git -C "$w" push -q origin main 2>/dev/null
  echo "$w"
}

steps_order() { grep -o '▸ 第 [0-9] 步' | grep -o '[0-9]' | tr -d '\n'; }

# ---------- A. dry-run，契约包 tag 远端还没有：六步按顺序，只打印改动类命令 ----------
W="$(fixture a go)"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(echo "$out" | steps_order)" = "123456" ]; then ok "A dry-run 六步按顺序"; else bad "A rc=$rc order=$(echo "$out" | steps_order)\n$out"; fi
echo "$out" | grep -q '\[dry-run\] git push origin main' && ok "A 打印 push main" || bad "A 没打印 push main"
echo "$out" | grep -q "gate config-key-scan --root $T/a --only components/demo/thing --strict" \
  && echo "$out" | grep -q "gate openapi-additive-scan --root $T/a --only components/demo/thing" \
  && echo "$out" | grep -q "门禁 be-acceptance@$(git -C "$ACC" rev-parse --short HEAD)" \
  && ok "A 发布前门禁照跑并打印命令（dry-run 也跑）" || bad "A 没打印发布前门禁命令:\n$out"
echo "$out" | grep -q '\[dry-run\] git tag -a gen/demo/thing/v1.0.0' && ok "A 打印契约包 tag" || bad "A 没打印契约包 tag:\n$out"
echo "$out" | grep -q '\[dry-run\] brickkit release --notes-file' && ok "A 打印 brickkit release" || bad "A 没打印 release"
echo "$out" | grep -q '\[dry-run\] git tag -a v2.0.0' && ok "A 打印 v tag" || bad "A 没打印 v tag"
[ -z "$(git -C "$W" ls-remote --tags origin)" ] && ok "A 远端没有任何 tag" || bad "A dry-run 推了 tag"
[ -z "$(git -C "$W" tag -l)" ] && ok "A 本地没有打 tag" || bad "A dry-run 打了本地 tag"
[ ! -s "$FAKE_CALLS" ] && ok "A 没调用 brickkit" || bad "A dry-run 调用了 brickkit: $(cat "$FAKE_CALLS")"

# ---------- B. N-3：已发布的契约包 tag 与 HEAD 的 gen/ 不一致 → 第 2 步 FAIL 即停 ----------
W="$(fixture b go)"
git -C "$W" tag -a gen/demo/thing/v1.0.0 -m t && git -C "$W" push -q origin gen/demo/thing/v1.0.0
printf 'package thing\n\nconst V = 2\n' > "$W/gen/demo/thing/thing.go"
git -C "$W" commit -q -am "改了契约" && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 2 步.*FAIL' && [ "$(echo "$out" | steps_order)" = "12" ]; then ok "B N-3 抓到契约包不一致并停在第 2 步"; else bad "B rc=$rc\n$out"; fi

# ---------- C. 契约包 tag 已发布且 gen/ 未变（只改了别处）→ 第 2 步 PASS ----------
W="$(fixture c go)"
git -C "$W" tag -a gen/demo/thing/v1.0.0 -m t && git -C "$W" push -q origin gen/demo/thing/v1.0.0
echo "// x" >> "$W/backend/module/module.go"
git -C "$W" commit -q -am "改了实现" && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '▸ 第 2 步.*PASS' && ! echo "$out" | grep -q 'git tag -a gen/'; then ok "C 已发布且一致的契约包：PASS，不重打"; else bad "C rc=$rc\n$out"; fi

# ---------- C2. 根 go.mod require 的契约包是占位 v0.0.0 → 第 2 步 FAIL ----------
W="$(fixture c2 go)"
sed -i 's| v1.0.0$| v0.0.0|' "$W/go.mod" && git -C "$W" commit -q -am "占位版本" && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 2 步.*FAIL.*v0.0.0'; then ok "C2 占位契约包版本 v0.0.0 被拒"; else bad "C2 rc=$rc\n$out"; fi

# ---------- D. 工作区不干净 → 第 1 步 FAIL ----------
W="$(fixture d go)"
echo x > "$W/untracked.txt"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL' && [ "$(echo "$out" | steps_order)" = "1" ]; then ok "D 脏工作区第 1 步即停"; else bad "D rc=$rc\n$out"; fi

# ---------- E. 不在 main → 第 1 步 FAIL ----------
W="$(fixture e go)"
git -C "$W" checkout -q -b feature
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL'; then ok "E 不在 main 即停"; else bad "E rc=$rc\n$out"; fi

# ---------- F. 发布说明在组件目录里 → 拒绝 ----------
W="$(fixture f go)"
out="$(bash "$SHIP" --dry-run "$W" "$W/component.yaml" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '目录之外'; then ok "F 说明文件在组件目录里被拒"; else bad "F rc=$rc\n$out"; fi

# ---------- G. Python 组件与外壳：跳过 2、4、5 ----------
W="$(fixture g python)"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
n="$(echo "$out" | grep -cE '▸ 第 [245] 步.*SKIP')"
if [ $rc -eq 0 ] && [ "$n" = 3 ] && [ "$(echo "$out" | steps_order)" = "123456" ]; then ok "G Python 组件跳过 2/4/5"; else bad "G rc=$rc n=$n\n$out"; fi
W="$(fixture h shell)"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
n="$(echo "$out" | grep -cE '▸ 第 [245] 步.*SKIP')"
if [ $rc -eq 0 ] && [ "$n" = 3 ] && echo "$out" | grep -q '1.0.0'; then ok "G 外壳跳过 2/4/5、版本 1.0.0"; else bad "G shell rc=$rc n=$n\n$out"; fi

# ---------- H. 真跑（Python，远端是 bare 仓库）：tag 在 HEAD；重跑不再调用 release ----------
W="$(fixture i python)"
: > "$FAKE_CALLS"
out="$(bash "$SHIP" "$W" "$T/notes.md" 2>&1)"; rc=$?
head_sha="$(git -C "$W" rev-parse HEAD)"
remote_sha="$(git -C "$W" ls-remote origin 'refs/tags/2.0.0^{}' | cut -f1)"
if [ $rc -eq 0 ] && [ "$remote_sha" = "$head_sha" ] && [ "$(git -C "$W" cat-file -t 2.0.0)" = tag ]; then ok "H 真跑：2.0.0 是注解 tag、在远端、指向 HEAD"; else bad "H rc=$rc remote=$remote_sha head=$head_sha\n$out"; fi
: > "$FAKE_CALLS"
out="$(bash "$SHIP" "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ ! -s "$FAKE_CALLS" ] && echo "$out" | grep -q '▸ 第 3 步.*PASS'; then ok "H 重跑：已发布即 PASS，不再调用 release"; else bad "H 重跑 rc=$rc calls=$(cat "$FAKE_CALLS")\n$out"; fi

# ---------- I. 已推送的 tag 指向别的提交 → FAIL，绝不移动 ----------
echo "// y" >> "$W/pyproject.toml"
git -C "$W" commit -q -am "又改了" && git -C "$W" push -q origin main
out="$(bash "$SHIP" "$W" "$T/notes.md" 2>&1)"; rc=$?
after="$(git -C "$W" ls-remote origin 'refs/tags/2.0.0^{}' | cut -f1)"
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 3 步.*FAIL' && [ "$after" = "$head_sha" ]; then ok "I tag 已在别的提交：FAIL 且远端 tag 未移动"; else bad "I rc=$rc after=$after\n$out"; fi

# ---------- J. 真跑（Go）：三个 tag 都推到 HEAD；拉取探针在 GOPROXY=off 下失败 → 停在第 5 步，已推送的不回滚 ----------
W="$(fixture j go)"
out="$(bash "$SHIP" "$W" "$T/notes.md" 2>&1)"; rc=$?
head_sha="$(git -C "$W" rev-parse HEAD)"
all_at_head=1
for t in 2.0.0 v2.0.0 gen/demo/thing/v1.0.0; do
  s="$(git -C "$W" ls-remote origin "refs/tags/$t^{}" | cut -f1)"
  [ "$s" = "$head_sha" ] || all_at_head=0
done
if [ $rc -ne 0 ] && [ $all_at_head = 1 ] && echo "$out" | grep -q '▸ 第 4 步.*PASS' && echo "$out" | grep -q '▸ 第 5 步.*FAIL' \
   && [ "$(echo "$out" | steps_order)" = "12345" ]; then ok "J Go 真跑：三个 tag 在 HEAD，探针失败停在第 5 步"; else bad "J rc=$rc at_head=$all_at_head\n$out"; fi

# ---------- K（修复轮 I-1）. 远端契约包 tag 在旧提交，本地同名 tag 却在 HEAD → 必须按远端比较并 FAIL ----------
W="$(fixture k go)"
git -C "$W" tag -a gen/demo/thing/v1.0.0 -m t && git -C "$W" push -q origin gen/demo/thing/v1.0.0
printf 'package thing\n\nconst V = 2\n' > "$W/gen/demo/thing/thing.go"
git -C "$W" commit -q -am "改了契约" && git -C "$W" push -q origin main
git -C "$W" tag -d gen/demo/thing/v1.0.0 >/dev/null && git -C "$W" tag -a gen/demo/thing/v1.0.0 -m local HEAD
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 2 步.*FAIL' && [ "$(echo "$out" | steps_order)" = "12" ]; then ok "K 本地同名 tag 与已发布的不同：第 2 步 FAIL"; else bad "K rc=$rc\n$out"; fi
# K2：本地没有这个 tag、远端有且与 HEAD 一致 → dry-run 照样 PASS，并且不在本地建 tag 引用
W="$(fixture k2 go)"
git -C "$W" tag -a gen/demo/thing/v1.0.0 -m t && git -C "$W" push -q origin gen/demo/thing/v1.0.0
git -C "$W" tag -d gen/demo/thing/v1.0.0 >/dev/null
echo "// x" >> "$W/backend/module/module.go"; git -C "$W" commit -q -am x && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '▸ 第 2 步.*PASS' && [ -z "$(git -C "$W" tag -l)" ]; then ok "K2 按远端 tag 比较，dry-run 不建本地 tag"; else bad "K2 rc=$rc tags=$(git -C "$W" tag -l)\n$out"; fi

# ---------- L（M-2）. component.yaml 没有 metadata.version → 第 1 步之前就失败 ----------
W="$(fixture l python)"
sed -i '/^  version:/d' "$W/component.yaml" && git -C "$W" commit -q -am "无版本" && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q 'metadata.version' && [ -z "$(echo "$out" | steps_order)" ]; then ok "L 没有版本号：开始前即拒绝"; else bad "L rc=$rc\n$out"; fi

# ---------- M（M-4）. 经符号链接路径调用 → 第 1 步照样 PASS ----------
W="$(fixture m python)"
ln -s "$W" "$T/m-link"
out="$(bash "$SHIP" --dry-run "$T/m-link" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '▸ 第 1 步.*PASS'; then ok "M 符号链接路径可用"; else bad "M rc=$rc\n$out"; fi

# ---------- N（M-3）. J 发布后本地 tag 全删（如新 clone）再重跑 → 第 2–4 步按远端判定 PASS ----------
W="$T/j/components/demo/thing"
git -C "$W" tag -d 2.0.0 v2.0.0 gen/demo/thing/v1.0.0 >/dev/null
: > "$FAKE_CALLS"
out="$(bash "$SHIP" "$W" "$T/notes.md" 2>&1)"; rc=$?
if echo "$out" | grep -q '▸ 第 2 步.*PASS' && echo "$out" | grep -q '▸ 第 3 步.*PASS' && echo "$out" | grep -q '▸ 第 4 步.*PASS' \
   && [ ! -s "$FAKE_CALLS" ]; then ok "N 只有远端 tag 时重跑：2–4 步 PASS、不再 release"; else bad "N rc=$rc calls=$(cat "$FAKE_CALLS")\n$out"; fi

# ---------- O（T7 审查 Important 2）. PATH 上的 brickkit 不是 v1.1.0 → 开始前即拒绝，点名二进制路径，什么都不推 ----------
W="$(fixture o python)"
: > "$FAKE_CALLS"
for mode in --dry-run ""; do
  out="$(FAKE_BK_VERSION=v0.4.6 bash "$SHIP" $mode "$W" "$T/notes.md" 2>&1)"; rc=$?
  if [ $rc -eq 2 ] && echo "$out" | grep -q "❌ PATH 上的 brickkit 是 $T/bin/brickkit：BrickKit CLI v0.4.6" \
     && [ -z "$(echo "$out" | steps_order)" ] && [ ! -s "$FAKE_CALLS" ] && [ -z "$(git -C "$W" ls-remote --tags origin)" ]; then
    ok "O 旧版 brickkit（${mode:-真跑}）：exit 2、点名 $T/bin/brickkit、一步都不走"
  else bad "O ${mode:-真跑} rc=$rc calls=$(cat "$FAKE_CALLS")\n$out"; fi
done

# ---------- P（T8b1 审查 Important 2）. 本组件 configSchema 键名违规 → 第 1 步 FAIL，推 main / 打 tag 之前就停 ----------
W="$(fixture p python)"
printf 'configSchema:\n  properties:\n    pgSchema: {type: string}\n' >> "$W/component.yaml"
git -C "$W" commit -q -am "驼峰键"          # 不推：真跑时必须连 main 都不推
for mode in --dry-run ""; do
  : > "$FAKE_CALLS"
  out="$(bash "$SHIP" $mode "$W" "$T/notes.md" 2>&1)"; rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*config-key-scan' && echo "$out" | grep -q 'pgSchema \[naming\]' \
     && ! echo "$out" | grep -q 'git push origin main' && [ "$(echo "$out" | steps_order)" = "1" ] && [ ! -s "$FAKE_CALLS" ] \
     && [ -z "$(git -C "$W" ls-remote --tags origin)" ] \
     && [ "$(git -C "$W" ls-remote origin refs/heads/main | cut -f1)" != "$(git -C "$W" rev-parse HEAD)" ]; then
    ok "P config-key-scan 红（${mode:-真跑}）：停在第 1 步，没推 main、没打 tag、没调 release"
  else bad "P ${mode:-真跑} rc=$rc calls=$(cat "$FAKE_CALLS")\n$out"; fi
done

# ---------- Q. 本组件 openapi 相对上一个发布 tag 删了路径 → 第 1 步 FAIL ----------
W="$(fixture q python)"
mkdir -p "$W/contracts"
printf 'openapi: 3.0.3\ninfo: {title: t, version: 1.0.0}\npaths:\n  /a:\n    get:\n      responses:\n        "200": {description: ok}\n  /b:\n    get:\n      responses:\n        "200": {description: ok}\n' > "$W/contracts/thing.openapi.yaml"
git -C "$W" add -A && git -C "$W" commit -q -m "1.x 契约" && git -C "$W" tag -a 1.0.0 -m 1.0.0
sed -i '/\/b:/,$d' "$W/contracts/thing.openapi.yaml"
git -C "$W" commit -q -am "删了 /b" && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*openapi-additive-scan' && echo "$out" | grep -q 'GET /b \[removed\]' \
   && [ "$(echo "$out" | steps_order)" = "1" ]; then ok "Q openapi-additive-scan 红：停在第 1 步"; else bad "Q rc=$rc\n$out"; fi

# ---------- R. 同一项目里别的 1.x 组件有违规（--strict 下也是 ✗）→ 只看本组件，不挡发布 ----------
W="$(fixture r python)"
mkdir -p "$T/r/components/old/legacy"
printf 'apiVersion: brickkit/v1\nkind: Component\nmetadata:\n  id: old/legacy\n  version: 1.0.0\nconfigSchema:\n  properties:\n    pgSchema: {type: string}\n' > "$T/r/components/old/legacy/component.yaml"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '▸ 第 1 步.*PASS' && echo "$out" | grep -q '✓ config-key-scan（只看 components/demo/thing）：0 条违规' \
   && ! echo "$out" | grep -q 'pgSchema'; then ok "R 别的组件的违规不挡本组件发布（--only 只扫本组件）"
else bad "R rc=$rc\n$out"; fi

# ---------- S. 远端有发布 tag、本地一个都没有（没 fetch tags）→ openapi 会"没有发布 tag，跳过"而假绿：第 1 步 FAIL ----------
W="$(fixture s python)"
git -C "$W" tag -a 1.0.0 -m 1.0.0 && git -C "$W" push -q origin 1.0.0 && git -C "$W" tag -d 1.0.0 >/dev/null
echo "# 2.x" >> "$W/pyproject.toml" && git -C "$W" commit -q -am "2.x" && git -C "$W" push -q origin main   # 1.0.0 是更早的版本
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*fetch --tags' && [ -z "$(git -C "$W" tag -l)" ]; then ok "S 本地缺发布 tag：第 1 步 FAIL，提示 fetch --tags（dry-run 不建本地 tag）"
else bad "S rc=$rc\n$out"; fi

# ---------- T（B2 审查 I-1）. 本地只有旧的 1.0.0、没有远端最新的 2.0.0 → 基线过旧，2.0.0 里新增又删掉的路径看不见：拒绝 ----------
W="$(fixture t python)"
spec="$W/contracts/thing.openapi.yaml"; mkdir -p "$W/contracts"
oa() { printf 'openapi: 3.0.3\ninfo: {title: t, version: 1.0.0}\npaths:\n'; for p in "$@"; do printf '  /%s:\n    get:\n      responses:\n        "200": {description: ok}\n' "$p"; done; }
oa a > "$spec"; git -C "$W" add -A && git -C "$W" commit -q -m "1.0.0：/a" && git -C "$W" tag -a 1.0.0 -m 1.0.0
oa a c > "$spec"; git -C "$W" commit -q -am "2.0.0：/a /c" && git -C "$W" tag -a 2.0.0 -m 2.0.0 && git -C "$W" tag -a v2.0.0 -m v2.0.0
git -C "$W" push -q origin main 1.0.0 2.0.0 v2.0.0 && git -C "$W" tag -d 2.0.0 v2.0.0 >/dev/null
oa a > "$spec"; sed -i 's/^  version: 2.0.0/  version: 2.1.0/' "$W/component.yaml"
git -C "$W" commit -q -am "2.1.0：删了 /c" && git -C "$W" push -q origin main
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*2\.0\.0.*fetch --tags' && [ "$(echo "$out" | steps_order)" = "1" ] \
   && ! echo "$out" | grep -q 'openapi-additive-scan --root'; then ok "T 本地缺远端最新的发布 tag 2.0.0：第 1 步 FAIL（门禁都没跑）"
else bad "T rc=$rc\n$out"; fi
# T2：本地有 2.0.0 但指向别的提交 → 同样拒绝；T3：fetch 回来之后按 2.0.0 比较，/c 被删判红
git -C "$W" tag -a 2.0.0 -m local HEAD~1~1 2>/dev/null || git -C "$W" tag -a 2.0.0 -m local "$(git -C "$W" rev-list --max-parents=0 HEAD)"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*2\.0\.0'; then ok "T2 本地 2.0.0 与远端不在同一提交：拒绝"; else bad "T2 rc=$rc\n$out"; fi
git -C "$W" tag -d 2.0.0 >/dev/null && git -C "$W" fetch -q --tags origin
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q 'GET /c \[removed\]' && echo "$out" | grep -q '对比 2.0.0'; then ok "T3 fetch 之后按 2.0.0 比较：删 /c 判红"
else bad "T3 rc=$rc\n$out"; fi

# ---------- V（I-3）. be-acceptance 工作区不干净 / HEAD 不是父仓库钉住的提交 → 拒绝，并提示先提交指针 ----------
W="$(fixture v python)"
echo x > "$ACC/stray.txt"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*be-acceptance.*不干净'; then ok "V be-acceptance 工作区不干净：拒绝"; else bad "V dirty rc=$rc\n$out"; fi
rm -f "$ACC/stray.txt"
git -C "$ACC" commit -q --allow-empty -m "没钉的提交"
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*钉住' && echo "$out" | grep -q '先提交'; then ok "V be-acceptance HEAD 不是钉住的提交：拒绝，提示先提交指针"
else bad "V unpinned rc=$rc\n$out"; fi
pin_acc
out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "V 钉上之后放行" || bad "V 钉上后 rc=$rc\n$out"

# ---------- U（I-2）. 判据是 gate 的退出码，不解析输出：把违规行改成别的格式（钉住）照样判红 ----------
sed -i 's|fmt.Fprintf(os.Stderr, "✗ %s:%d：%s \[%s\] %s\\n"|fmt.Fprintf(os.Stderr, "VIOLATION %s:%d：%s [%s] %s\\n"|' "$ACC/cmd/be-acceptance/main.go"
if git -C "$ACC" diff --quiet; then bad "U 没改到 be-acceptance 的输出格式（sed 没命中）"; else
  git -C "$ACC" commit -q -am "改输出格式" && pin_acc
  W="$(fixture u python)"
  printf 'configSchema:\n  properties:\n    pgSchema: {type: string}\n' >> "$W/component.yaml"
  git -C "$W" commit -q -am "驼峰键" && git -C "$W" push -q origin main
  out="$(bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -q 'VIOLATION components/demo/thing/component.yaml' && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*config-key-scan'; then
    ok "U 违规行换了格式：照样按退出码判红"; else bad "U rc=$rc\n$out"; fi
fi

# ---------- W（M-4）. be-acceptance 编不过 → 第 1 步 FAIL，临时目录不留下 ----------
echo 'package main; func 坏(' >> "$ACC/cmd/be-acceptance/main.go"
git -C "$ACC" commit -q -am "编不过" && pin_acc
W="$(fixture w python)"
mkdir -p "$T/tmpx"
out="$(TMPDIR="$T/tmpx" bash "$SHIP" --dry-run "$W" "$T/notes.md" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -q '▸ 第 1 步.*FAIL.*构建 be-acceptance 失败' && [ -z "$(ls -A "$T/tmpx")" ]; then ok "W 门禁编不过：FAIL，临时目录已清掉"
else bad "W rc=$rc left=$(ls -A "$T/tmpx")\n$out"; fi

[ $fail -eq 0 ] && echo "全部通过" || echo "有失败"
exit $fail
