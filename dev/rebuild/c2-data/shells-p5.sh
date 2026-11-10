#!/bin/bash
# C2 P5: the Go shells on erp/purchase 3.0.0 (a new member of be/go-core), the sources its seed needed (mdm/partner
# 3.0.40, infra/iam-casdoor 3.0.44) and their cascade (credit 3.0.38, sales 3.0.47, billing 3.0.56). Made from
# shells-p0b.sh. Output in shells-p5.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p5.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V=([infra/audit]=3.0.38 [infra/authz]=3.0.48 [infra/iam-casdoor]=3.0.44 [mdm/currency]=3.0.33 [mdm/org]=3.0.35
  [mdm/employee]=3.0.3 [mdm/partner]=3.0.40 [mdm/product]=3.0.37 [erp/credit]=3.0.38 [erp/inventory]=3.0.37
  [erp/sales]=3.0.47 [erp/billing]=3.0.56 [erp/purchase]=3.0.0)
PROBE=3.2.52; SDK=v3.0.0-alpha.121; declare -A NEWV=([go-infra]=3.0.78 [go-core]=3.0.83)
# SHELLS (default both): the shells to do
for shell in ${SHELLS:-go-infra go-core}; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${NEWV[$shell]}
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    if [ $shell = go-core ] && ! grep -q "erp/purchase@" component.yaml; then  # the purchase member joins (C2)
      sed -i "s#^    - erp/billing@\(.*\)#    - erp/billing@\1\n    - erp/purchase@${V[erp/purchase]}#" component.yaml
      sed -i 's#\t"github.com/brickKit/erp-inventory/v3/inventory"#\t"github.com/brickKit/erp-inventory/v3/inventory"\n\t"github.com/brickKit/erp-purchase/v3/purchase"#' members.go
      sed -i 's#billing.Definition())#billing.Definition(), purchase.Definition())#' members.go
    fi
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
    f=$(mktemp); printf 'be/%s %s: erp/purchase 3.0.0 joins the core shell; the members released with it (C2 P5)%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '核心外壳加入 erp/purchase 3.0.0（装配项目阶段计划 C2）；成员换到为采购的种子补的源头版本（mdm/partner 3.0.40 的供应商角色、infra/iam-casdoor 3.0.44 的采购账号）与随它们连锁发布的版本%s。\n' "" > $n
    brickkit release --notes-file $n > $O/release-p5-$shell.log 2>&1; tail -3 $O/release-p5-$shell.log
    grep -q "Released" $O/release-p5-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e, and the first run
  # released be/go-infra 3.0.73 after its go get and tests had failed
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
