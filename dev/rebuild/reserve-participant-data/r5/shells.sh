#!/bin/bash
# R5: the Go shells on the members' alpha.117 releases and the Go probes 3.2.49 (from t11a/shells.sh).
# tidy, vet, tests, commit, push, brickkit release. Output in shells.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod
declare -A V=([infra/iam-casdoor]=3.0.41 [infra/authz]=3.0.43 [infra/audit]=3.0.36 [mdm/org]=3.0.32
  [mdm/currency]=3.0.31 [mdm/partner]=3.0.35 [mdm/product]=3.0.34 [erp/inventory]=3.0.33 [erp/credit]=3.0.33
  [erp/sales]=3.0.42 [erp/billing]=3.0.41)
PROBES=3.2.49; SDK=v3.0.0-alpha.117
for shell in go-infra go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml) ; NEW=$(echo $old | awk -F. '{print $1"."$2"."$3+1}')
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
    f=$(mktemp); printf 'be/%s %s: members on be-sdk-go alpha.117 (one version across the system), the Go probes %s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "$PROBES" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到 be-sdk-go alpha.117 的发布（全系统同一个版本；SDK 加了预占的参与方 `reserve`，`erp/credit`、`erp/inventory` 改用它），Go 探针 %s。\n' "$PROBES" > $n
    brickkit release --notes-file $n > $O/release-$shell.log 2>&1; tail -3 $O/release-$shell.log
    grep -q "Released" $O/release-$shell.log
  ) || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
