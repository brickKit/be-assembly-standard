#!/bin/bash
# C7 P6: be/go-infra and be/go-core with the members at their C7 P6 versions (the seeds of the approvals); the Go probe and
# 3.2.54. Made from c6-data/shells.sh; the
# member versions are read from their component.yaml, not typed. Output
# in shells.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V
for f in $R/components/*/*/component.yaml; do
  id=$(sed -n 's/^  id: //p' $f | head -1); v=$(sed -n 's/^  version: //p' $f | head -1)
  case $v in 3.*) V[$id]=$v;; esac
done
PROBE=$(sed -n 's/^  version: //p' $R/tools/be-acceptance/probes/go/component.yaml | head -1); SDK=v3.0.0-alpha.125
for shell in go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${old%.*}.$(( ${old##*.} + 1 ))
  echo "SHELLS $shell BEGIN $old -> $NEW (sdk $SDK, probe $PROBE)"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    sed -i -E "s#    - (test/probe-go[0-9]*)@[0-9.]+#    - \1@$PROBE#" component.yaml
    mods="github.com/brickKit/be-sdk-go/v3@$SDK github.com/brickKit/be-acceptance/probes/go/v3@v$PROBE"
    for id in "${!V[@]}"; do
      if grep -q "    - $id@" component.yaml; then
        sed -i -E "s#    - $id@[0-9.]+#    - $id@${V[$id]}#" component.yaml
        mods="$mods github.com/brickKit/${id/\//-}/v3@v${V[$id]}"
      fi
    done
    go get $mods
    go mod tidy
    gofmt -l . | (! grep .)
    go vet ./...
    go test -count=1 ./...
    grep -q "version: $NEW" component.yaml && grep -q "\"$NEW\"" main.go
    brickkit lint
    git add -A && git diff --cached --stat
    extra=": the seeds of the approvals"
    f=$(mktemp); printf 'be/%s %s: the members at their C7 P6 versions%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "$extra" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员跟到 C7 P6 的版本：mdm/employee 3.0.7（种子关联审批人）、infra/workflow 3.0.1（种子）、erp/purchase 3.0.9、erp/payment 3.0.13（种子的付款政策）；外壳本身不变。\n' > $n
    brickkit release --notes-file $n > $O/release-$shell.log 2>&1; tail -3 $O/release-$shell.log
    grep -q "Released" $O/release-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
