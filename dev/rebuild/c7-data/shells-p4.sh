#!/bin/bash
# C7 P4: be/go-infra and be/go-core on be-sdk-go alpha.125 (the flow kernel), every member's new version and the Go probe
# 3.2.54. Made from c6-data/shells-p4.sh; the
# member versions are read from their component.yaml, not typed. Output
# in shells-p4.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p4.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V
for f in $R/components/*/*/component.yaml; do
  id=$(sed -n 's/^  id: //p' $f | head -1); v=$(sed -n 's/^  version: //p' $f | head -1)
  case $v in 3.*) V[$id]=$v;; esac
done
PROBE=$(sed -n 's/^  version: //p' $R/tools/be-acceptance/probes/go/component.yaml | head -1); SDK=v3.0.0-alpha.125
for shell in go-infra go-core; do
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
    extra=""; [ $shell = go-infra ] && extra="; it hosts infra/workflow"
    f=$(mktemp); printf 'be/%s %s: be-sdk-go alpha.125 and the members on it%s (C7 P4)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "$extra" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf 'be-sdk-go alpha.125（全系统同一个 SDK 版本，流程内核为审批迁移补的几样）；成员都换到用它的版本（采购 3.0.8、收付款 3.0.12 的审批走流程内核），Go 探针 3.2.54%s\n' "$([ $shell = go-infra ] && echo '；本外壳加了统一待办 infra/workflow 3.0.0' || echo '。')" > $n
    brickkit release --notes-file $n > $O/release-p4-$shell.log 2>&1; tail -3 $O/release-p4-$shell.log
    grep -q "Released" $O/release-p4-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
