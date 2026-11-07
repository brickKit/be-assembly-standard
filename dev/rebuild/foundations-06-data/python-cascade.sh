#!/bin/bash
# The Python members' cascade of foundations item 6, after a be-sdk-python release: erp/billing on the new infra/print,
# be/go-core on that billing, be/py-render on the SDK, the Python probes and infra/print. Each: version up, pins, tests,
# lint, commit, push, brickkit release. (From t3/shells.sh and t4/shells.sh.)
# Usage: PYSDK=v3.0.0aNN PYPROBES=3.2.NN PRINT=3.0.NN python-cascade.sh <out dir>
# Output in <out dir>/cascade.log; "CASCADE ALL-DONE" or "CASCADE FAILED <step>".
set -u
: "${PYSDK:?}" "${PYPROBES:?}" "${PRINT:?}"
R=/home/zhijie/Desktop/github/be-assembly-standard; O="${1:?out dir}"; mkdir -p "$O"
echo $$ > "$O/cascade.pid"
exec >> "$O/cascade.log" 2>&1
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod PYTHONDONTWRITEBYTECODE=1
set -a; . $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1; set +a
bump() { echo "$1" | awk -F. '{print $1"."$2"."$3+1}'; }
release() {  # $1 name, $2 commit subject, $3 Chinese notes
  brickkit lint
  git add -A && git diff --cached --stat
  f=$(mktemp); printf '%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$2" > $f
  git commit -q -F $f && git log -1 --format='%h %s'
  git push -q
  n=$(mktemp); printf '%s\n' "$3" > $n
  brickkit release --notes-file $n > $O/release-$1.log 2>&1; tail -3 $O/release-$1.log
  grep -q "Released" $O/release-$1.log
}
step=erp-billing; d=$R/components/erp/billing; old=$(sed -n 's/^  version: //p' $d/component.yaml); BILLING=$(bump $old)
echo "CASCADE $step BEGIN $old -> $BILLING"
(
  set -e; cd $d
  sed -i "s/^  version: $old$/  version: $BILLING/; s#    - id: infra/print@[0-9.]*#    - id: infra/print@$PRINT#" component.yaml
  sed -i "s/	Version  = \"$old\"/	Version  = \"$BILLING\"/" billing/definition.go
  python3 - "$BILLING" "$PRINT" "$PYSDK" <<'PY'
import pathlib, sys
p = pathlib.Path("docs/design.md"); s = p.read_text(); old = "## 实现状态\n\n"
assert old in s
p.write_text(s.replace(old, old + f"{sys.argv[1]}：依赖换到 `infra/print` {sys.argv[2]}（打印组件换上 be-sdk-python {sys.argv[3]}；契约不变）。\n\n", 1))
PY
  grep -q "version: $BILLING" component.yaml && grep -q "\"$BILLING\"" billing/definition.go && grep -q "infra/print@$PRINT" component.yaml
  go vet ./... && go test -count=1 ./... && make test-integration
  release $step "erp/billing $BILLING on infra/print $PRINT" "依赖换到 \`infra/print\` $PRINT（打印组件换上 be-sdk-python $PYSDK；契约不变）。"
) || { echo "CASCADE FAILED $step"; exit 1; }
echo "CASCADE $step END $BILLING"
step=go-core; d=$R/shell/be/go-core; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=$(bump $old)
echo "CASCADE $step BEGIN $old -> $NEW"
(
  set -e; cd $d
  sed -i "s/^  version: $old$/  version: $NEW/; s#    - erp/billing@[0-9.]*#    - erp/billing@$BILLING#" component.yaml
  sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
  go get github.com/brickKit/erp-billing/v3@v$BILLING
  go mod tidy && go vet ./... && go test -count=1 ./...
  grep -q "version: $NEW" component.yaml && grep -q "\"$NEW\"" main.go && grep -q "erp/billing@$BILLING" component.yaml
  release $step "be/go-core $NEW: erp/billing $BILLING" "\`erp/billing\` $BILLING（依赖 \`infra/print\` $PRINT）。"
) || { echo "CASCADE FAILED $step"; exit 1; }
echo "CASCADE $step END $NEW"
step=py-render; d=$R/shell/be/py-render; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=$(bump $old)
echo "CASCADE $step BEGIN $old -> $NEW"
(
  set -e; cd $d
  sed -i "s/^  version: $old$/  version: $NEW/" component.yaml
  sed -i "s/^version = \"$old\"/version = \"$NEW\"/" pyproject.toml
  sed -i -E "s#(test/probe-py2?)@3\.2\.[0-9]+#\1@$PYPROBES#; s#infra/print@3\.0\.[0-9]+#infra/print@$PRINT#" component.yaml
  sed -i -E "s#be-sdk-python@v3\.0\.0a[0-9]+#be-sdk-python@$PYSDK#; s#(be-sdk = \{ git = \"https://github.com/brickKit/be-sdk-python\", tag = \")v3\.0\.0a[0-9]+#\1$PYSDK#" pyproject.toml
  sed -i -E "s#tag = \"test-probe-py/3\.2\.[0-9]+\"#tag = \"test-probe-py/$PYPROBES\"#; s#(infra-print\", tag = \")3\.0\.[0-9]+#\1$PRINT#" pyproject.toml
  sed -i -E "s|^# one SDK in the process: .*|# one SDK in the process: the one every Python member runs ($PYSDK: the probes $PYPROBES and infra/print $PRINT)|" pyproject.toml
  uv lock
  grep -q "version: $NEW" component.yaml && grep -q "^version = \"$NEW\"" pyproject.toml
  grep -q "test-probe-py/$PYPROBES" pyproject.toml && grep -q "infra-print\", tag = \"$PRINT\"" pyproject.toml
  grep -q "be-sdk-python@$PYSDK" pyproject.toml
  uv run --frozen pytest -q -p no:cacheprovider tests
  release $step "be/py-render $NEW: be-sdk-python $PYSDK, the Python probes $PYPROBES, infra/print $PRINT" \
    "be-sdk-python $PYSDK；Python 探针 $PYPROBES、\`infra/print\` $PRINT。"
) || { echo "CASCADE FAILED $step"; exit 1; }
echo "CASCADE $step END $NEW"
echo "CASCADE ALL-DONE"
