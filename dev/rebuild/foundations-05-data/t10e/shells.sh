#!/bin/bash
# T10e step 2: the Go shells on the members' alpha.115 releases and the Go probes 3.2.47: version up, members, go get,
# tidy, vet, tests, commit, push, brickkit release. Output in shells.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod
declare -A V=([infra/iam-casdoor]=3.0.37 [infra/authz]=3.0.40 [infra/audit]=3.0.31 [mdm/org]=3.0.28
  [mdm/currency]=3.0.27 [mdm/partner]=3.0.31 [mdm/product]=3.0.30 [erp/inventory]=3.0.27 [erp/credit]=3.0.27
  [erp/sales]=3.0.36 [erp/billing]=3.0.36)
PROBES=3.2.47; SDK=v3.0.0-alpha.115; NEW=3.0.64
for shell in go-infra go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml)
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    sed -i -E "s#(test/probe-go[0-9]*)@3\.2\.[0-9]+#\1@$PROBES#" component.yaml
    mods="github.com/brickKit/be-sdk-go/v3@$SDK github.com/brickKit/be-acceptance/probes/go/v3@v$PROBES"
    for id in "${!V[@]}"; do
      if grep -q "    - $id@" component.yaml; then
        sed -i -E "s#    - $id@[0-9.]+#    - $id@${V[$id]}#" component.yaml
        mods="$mods github.com/brickKit/${id/\//-}/v3@v${V[$id]}"
      fi
    done
    go get $mods
    go mod tidy
    go vet ./...
    go test -count=1 ./...
    grep -q "version: $NEW" component.yaml && grep -q "\"$NEW\"" main.go
    brickkit lint
    git add -A && git diff --cached --stat
    f=$(mktemp); printf 'be/%s %s: members on be-sdk-go alpha.115 (one version across the system), the Go probes %s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "$PROBES" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到 be-sdk-go alpha.115 的发布（全系统同一个版本；审计记录与已结束的销售订单可以转层），Go 探针 %s。\n' "$PROBES" > $n
    brickkit release --notes-file $n > $O/release-$shell.log 2>&1; tail -3 $O/release-$shell.log
    grep -q "Released" $O/release-$shell.log
  ) || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
