#!/bin/bash
# T4 of foundations item 6: be/go-core on erp/billing 3.0.44; be/py-render on be-sdk-python a53, the Python probes
# 3.2.44 and infra/print 3.0.17 (from t3/shells.sh). Output in shells.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod PYTHONDONTWRITEBYTECODE=1
BILLING=3.0.44; PYPROBES=3.2.44; PRINT=3.0.17; PYSDK=v3.0.0a53
bump() { echo "$1" | awk -F. '{print $1"."$2"."$3+1}'; }
release() {  # $1 shell, $2 commit subject, $3 Chinese notes
  brickkit lint
  git add -A && git diff --cached --stat
  f=$(mktemp); printf '%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$2" > $f
  git commit -q -F $f && git log -1 --format='%h %s'
  git push -q
  n=$(mktemp); printf '%s\n' "$3" > $n
  brickkit release --notes-file $n > $O/release-$1.log 2>&1; tail -3 $O/release-$1.log
  grep -q "Released" $O/release-$1.log
}
shell=go-core; d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=$(bump $old)
echo "SHELLS $shell BEGIN $old -> $NEW"
(
  set -e; cd $d
  sed -i "s/^  version: $old/  version: $NEW/" component.yaml
  sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
  sed -i -E "s#    - erp/billing@[0-9.]+#    - erp/billing@$BILLING#" component.yaml
  go get github.com/brickKit/erp-billing/v3@v$BILLING
  go mod tidy && go vet ./... && go test -count=1 ./...
  grep -q "version: $NEW" component.yaml && grep -q "\"$NEW\"" main.go && grep -q "erp/billing@$BILLING" component.yaml
  release $shell "be/$shell $NEW: erp/billing $BILLING" "\`erp/billing\` $BILLING（依赖 \`infra/print\` $PRINT）。"
) || { echo "SHELLS FAILED $shell"; exit 1; }
echo "SHELLS $shell END $NEW"
shell=py-render; d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=$(bump $old)
echo "SHELLS $shell BEGIN $old -> $NEW"
(
  set -e; cd $d
  sed -i "s/^  version: $old/  version: $NEW/" component.yaml
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
  release $shell "be/$shell $NEW: be-sdk-python $PYSDK, the Python probes $PYPROBES, infra/print $PRINT" \
    "be-sdk-python $PYSDK（后台工作项、幂等键、分区维护）；Python 探针 $PYPROBES（后台工作项）、\`infra/print\` $PRINT。"
) || { echo "SHELLS FAILED $shell"; exit 1; }
echo "SHELLS $shell END $NEW"
echo "SHELLS ALL-DONE"
