#!/bin/bash
# C4 P5 (second): be/go-core on erp/finance 3.0.1 after the consistency exam; first: erp/finance 3.0.0 (a new member of be/go-core), erp/purchase 3.0.2 (the match basis it
# needs) and infra/iam-casdoor 3.0.46 (the finance accounts). Made from c2-data/shells-p5b.sh. Output in
# shells-p5.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p5b.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V=([infra/audit]=3.0.38 [infra/authz]=3.0.48 [infra/iam-casdoor]=3.0.46 [mdm/currency]=3.0.33 [mdm/org]=3.0.35
  [mdm/employee]=3.0.3 [mdm/partner]=3.0.40 [mdm/product]=3.0.38 [erp/credit]=3.0.38 [erp/inventory]=3.0.38
  [erp/sales]=3.0.48 [erp/billing]=3.0.57 [erp/purchase]=3.0.2 [erp/finance]=3.0.1)
PROBE=3.2.52; SDK=v3.0.0-alpha.121; declare -A NEWV=([go-infra]=none [go-core]=3.0.87)
# SHELLS (default both): the shells to do
for shell in ${SHELLS:-go-infra go-core}; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${NEWV[$shell]}
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    if [ $shell = go-core ] && ! grep -q "erp/finance@" component.yaml; then  # the finance member joins (C4)
      sed -i "s#^    - erp/purchase@\(.*\)#    - erp/purchase@\1\n    - erp/finance@${V[erp/finance]}#" component.yaml
      sed -i 's#\t"github.com/brickKit/erp-credit/v3/credit"#\t"github.com/brickKit/erp-credit/v3/credit"\n\t"github.com/brickKit/erp-finance/v3/finance"#' members.go
      sed -i 's#purchase.Definition())#purchase.Definition(), finance.Definition())#' members.go
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
    f=$(mktemp); printf 'be/%s %s: erp/finance 3.0.1 (an approved invoice difference holds for its results only; C4 P5)%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf 'erp/finance 换到 3.0.1（批准的供应商票据差异只对批准时的匹配结果有效）%s。\n' "" > $n
    brickkit release --notes-file $n > $O/release-p5b-$shell.log 2>&1; tail -3 $O/release-p5b-$shell.log
    grep -q "Released" $O/release-p5b-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e, and the first run
  # released be/go-infra 3.0.73 after its go get and tests had failed
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
