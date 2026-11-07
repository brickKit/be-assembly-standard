#!/bin/bash
# T3 of foundations item 6: the shells on the probes that declare RECOVERY_PHASE (Go 3.2.50, Python 3.2.43) and the
# Python shell on be-sdk-python a52 with infra/print 3.0.16 (from reserve-participant-data/r5/shells.sh).
# Each shell: version up, pins, tidy or lock, vet and tests, lint, commit, push, brickkit release. Output in shells.log;
# "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod PYTHONDONTWRITEBYTECODE=1
GOPROBES=3.2.50; PYPROBES=3.2.43; PRINT=3.0.16; PYSDK=v3.0.0a52
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
for shell in go-infra go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=$(bump $old)
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    sed -i -E "s#(test/probe-go[0-9]*)@3\.2\.[0-9]+#\1@$GOPROBES#" component.yaml
    go get github.com/brickKit/be-acceptance/probes/go/v3@v$GOPROBES
    go mod tidy && go vet ./... && go test -count=1 ./...
    grep -q "version: $NEW" component.yaml && grep -q "\"$NEW\"" main.go
    release $shell "be/$shell $NEW: the Go probes $GOPROBES (their manifests declare RECOVERY_PHASE)" \
      "Go 探针 $GOPROBES（清单声明 \`RECOVERY_PHASE\`，整套恢复时参加各阶段）。"
  ) || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
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
    "be-sdk-python $PYSDK（协议 alpha.116、整套恢复的阶段）；Python 探针 $PYPROBES、\`infra/print\` $PRINT。"
) || { echo "SHELLS FAILED $shell"; exit 1; }
echo "SHELLS $shell END $NEW"
echo "SHELLS ALL-DONE"
