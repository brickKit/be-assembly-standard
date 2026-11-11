#!/bin/bash
# C5 P5: be/go-core takes erp/costing 3.0.0 as a new member, and the members' current versions (erp/purchase 3.0.4
# and its cascade). Made from shells-p0c.sh; the member versions are read from their component.yaml, not typed. Output
# in shells-p5.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p5.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V
for f in $R/components/*/*/component.yaml; do
  id=$(sed -n 's/^  id: //p' $f | head -1); v=$(sed -n 's/^  version: //p' $f | head -1)
  case $v in 3.*) V[$id]=$v;; esac
done
PROBE=$(sed -n 's/^  version: //p' $R/tools/be-acceptance/probes/go/component.yaml | head -1); SDK=v3.0.0-alpha.121
for shell in go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${old%.*}.$(( ${old##*.} + 1 ))
  echo "SHELLS $shell BEGIN $old -> $NEW (erp/costing ${V[erp/costing]}, erp/purchase ${V[erp/purchase]}, erp/finance ${V[erp/finance]}, erp/payment ${V[erp/payment]}, probe $PROBE)"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    if ! grep -q "erp/costing@" component.yaml; then  # the costing member joins (C5)
      sed -i "s#^    - erp/payment@\(.*\)#    - erp/payment@\1\n    - erp/costing@${V[erp/costing]}#" component.yaml
      sed -i 's#\t"github.com/brickKit/erp-credit/v3/credit"#\t"github.com/brickKit/erp-costing/v3/costing"\n\t"github.com/brickKit/erp-credit/v3/credit"#' members.go
      sed -i 's#payment.Definition())#payment.Definition(), costing.Definition())#' members.go
      sed -i 's#、`erp/finance`、`erp/payment`。#、`erp/finance`、`erp/payment`、`erp/costing`。#' BRICKKIT.md
      grep -q '`erp/costing`。' BRICKKIT.md
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
    f=$(mktemp); printf 'be/%s %s: erp/costing %s joins the core shell; erp/purchase %s and its cascade (C5 P5)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "${V[erp/costing]}" "${V[erp/purchase]}" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '核心外壳加入 erp/costing %s（存货成本）；成员换到 erp/purchase %s（退货前问成本组件的可退数量）、erp/finance %s、erp/payment %s。\n' "${V[erp/costing]}" "${V[erp/purchase]}" "${V[erp/finance]}" "${V[erp/payment]}" > $n
    brickkit release --notes-file $n > $O/release-p5-$shell.log 2>&1; tail -3 $O/release-p5-$shell.log
    grep -q "Released" $O/release-p5-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
