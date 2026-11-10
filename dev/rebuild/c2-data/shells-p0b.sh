#!/bin/bash
# C2 P0b: the Go shells on the members released for the purchase component's sources: mdm/partner 3.0.39 (the supplier
# role), erp/inventory 3.0.37 (purchase receipts and returns) and the cascade (credit, sales, billing). Made from
# c1-data/shells-e6.sh. Output in shells.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V=([infra/audit]=3.0.38 [infra/authz]=3.0.48 [infra/iam-casdoor]=3.0.43 [mdm/currency]=3.0.33 [mdm/org]=3.0.35
  [mdm/employee]=3.0.3 [mdm/partner]=3.0.39 [mdm/product]=3.0.37 [erp/credit]=3.0.37 [erp/inventory]=3.0.37
  [erp/sales]=3.0.46 [erp/billing]=3.0.55)
PROBE=3.2.52; SDK=v3.0.0-alpha.121; declare -A NEWV=([go-infra]=3.0.77 [go-core]=3.0.82)
# SHELLS (default both): the shells to do
for shell in ${SHELLS:-go-infra go-core}; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${NEWV[$shell]}
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    if [ $shell = go-infra ] && ! grep -q "mdm/employee@" component.yaml; then  # the employee member joins (C1)
      sed -i "s#^    - mdm/org@\(.*\)#    - mdm/org@\1\n    - mdm/employee@${V[mdm/employee]}#" component.yaml
      sed -i 's#\t"github.com/brickKit/mdm-currency/v3/currency"#\t"github.com/brickKit/mdm-currency/v3/currency"\n\t"github.com/brickKit/mdm-employee/v3/employee"#' members.go
      sed -i 's#org.Definition(),#org.Definition(), employee.Definition(),#' members.go
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
    f=$(mktemp); printf 'be/%s %s: the members released for the sources of erp/purchase (C2 P0b)%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到为采购补的源头版本（mdm/partner 3.0.39 的供应商角色、erp/inventory 3.0.37 的采购收货与退货）与随它们连锁发布的版本，行为不变%s。\n' "" > $n
    brickkit release --notes-file $n > $O/release-$shell.log 2>&1; tail -3 $O/release-$shell.log
    grep -q "Released" $O/release-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e, and the first run
  # released be/go-infra 3.0.73 after its go get and tests had failed
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
