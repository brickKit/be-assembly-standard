#!/bin/bash
# C3 P5: the Go shells on erp/payment 3.0.0 (a new member of be/go-core), erp/finance 3.0.2 (the transfers in pairs)
# and infra/iam-casdoor 3.0.47 (the cashier). Made from c4-data/shells-p5.sh. Output in shells-p5.log;
# "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p5d.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V=([infra/audit]=3.0.38 [infra/authz]=3.0.48 [infra/iam-casdoor]=3.0.47 [mdm/currency]=3.0.33 [mdm/org]=3.0.35
  [mdm/employee]=3.0.3 [mdm/partner]=3.0.40 [mdm/product]=3.0.38 [erp/credit]=3.0.38 [erp/inventory]=3.0.38
  [erp/sales]=3.0.48 [erp/billing]=3.0.57 [erp/purchase]=3.0.2 [erp/finance]=3.0.3 [erp/payment]=3.0.2)
PROBE=3.2.52; SDK=v3.0.0-alpha.121; declare -A NEWV=([go-infra]=none [go-core]=3.0.91)
# SHELLS (default both): the shells to do
for shell in ${SHELLS:-go-infra go-core}; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${NEWV[$shell]}
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    if [ $shell = go-core ] && ! grep -q "erp/payment@" component.yaml; then  # the payment member joins (C3)
      sed -i "s#^    - erp/finance@\(.*\)#    - erp/finance@\1\n    - erp/payment@${V[erp/payment]}#" component.yaml
      sed -i 's#\t"github.com/brickKit/erp-inventory/v3/inventory"#\t"github.com/brickKit/erp-inventory/v3/inventory"\n\t"github.com/brickKit/erp-payment/v3/payment"#' members.go
      sed -i 's#finance.Definition())#finance.Definition(), payment.Definition())#' members.go
      sed -i 's#`erp/purchase`、`erp/finance`。#`erp/purchase`、`erp/finance`、`erp/payment`。#' BRICKKIT.md
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
    f=$(mktemp); printf 'be/%s %s: erp/finance 3.0.3 (its contract alpha.3 in a version; C3 P5)%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf 'erp/finance 换到 3.0.3（契约 alpha.3 纳入版本，行为不变）%s。\n' "" > $n
    brickkit release --notes-file $n > $O/release-p5d-$shell.log 2>&1; tail -3 $O/release-p5d-$shell.log
    grep -q "Released" $O/release-p5d-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e, and the first run
  # released be/go-infra 3.0.73 after its go get and tests had failed
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
