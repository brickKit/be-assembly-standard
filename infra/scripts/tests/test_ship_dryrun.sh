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

# fixture <名字> <go|python|shell>：建 bare 远端 + clone，提交并推送 main，回显工作目录
fixture() {
  local name="$1" kind="$2" w="$T/$1/work" r="$T/$1/remote.git"
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
W="$T/j/work"
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

[ $fail -eq 0 ] && echo "全部通过" || echo "有失败"
exit $fail
