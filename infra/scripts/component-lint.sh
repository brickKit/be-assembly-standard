#!/usr/bin/env bash
# 只 lint 一个组件（或外壳）：make docs-check ID=<scope>/<name>
# 原因：项目内 `brickkit lint` 会向上找到最近的 brickkit.yaml 并 lint 整个项目，没有限定到单个组件的开关
# （已作为反馈 F06-004 报给 brickKit）。绕过办法：把组件工作树拷到项目外的临时目录，
# 那里只有 component.yaml 没有 brickkit.yaml，brickKit 就把它当成独立的组件仓库。
# 用法：component-lint.sh <目录> [brickkit lint 的额外参数，默认 --strict]
set -euo pipefail

dir="${1:-}"
[ -n "$dir" ] && [ -f "$dir/component.yaml" ] || { echo "用法：component-lint.sh <含 component.yaml 的目录> [lint 参数]" >&2; exit 2; }
shift
[ $# -gt 0 ] || set -- --strict

src="$(cd "$dir" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
dst="$tmp/$(basename "$src")"
mkdir -p "$dst"

excl=(--exclude=.git --exclude=node_modules --exclude=dist --exclude=.venv --exclude=__pycache__
      --exclude=build --exclude=bin --exclude=target --exclude=.pytest_cache --exclude=coverage)
# 已跟踪 + 未跟踪（尊重 .gitignore）；不是 git 仓库时退回按排除表整树拷贝
if git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
  (cd "$src" && git ls-files -z --cached --others --exclude-standard | tar --null "${excl[@]}" -T - -cf -) | tar -xf - -C "$dst"
else
  (cd "$src" && tar "${excl[@]}" -cf - .) | tar -xf - -C "$dst"
fi

set +e
(cd "$dst" && brickkit lint "$@") 2>&1 | sed -e "s#$dst/##g" -e "s#$dst#.#g"
rc=${PIPESTATUS[0]}
exit "$rc"
