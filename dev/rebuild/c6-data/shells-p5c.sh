#!/bin/bash
# C6 P5 (the close): be/go-core on crm/opportunity 3.0.2 (its design without plan references). Made from shells-p5b.sh; the
# member versions are read from their component.yaml, not typed. Output
# in shells-p5c.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p5c.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V
for f in $R/components/*/*/component.yaml; do
  id=$(sed -n 's/^  id: //p' $f | head -1); v=$(sed -n 's/^  version: //p' $f | head -1)
  case $v in 3.*) V[$id]=$v;; esac
done
PROBE=$(sed -n 's/^  version: //p' $R/tools/be-acceptance/probes/go/component.yaml | head -1); SDK=v3.0.0-alpha.121
for shell in go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${old%.*}.$(( ${old##*.} + 1 ))
  echo "SHELLS $shell BEGIN $old -> $NEW (crm/opportunity ${V[crm/opportunity]}, erp/sales ${V[erp/sales]}, erp/billing ${V[erp/billing]}, erp/payment ${V[erp/payment]}, probe $PROBE)"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    if ! grep -q "crm/opportunity@" component.yaml; then  # the opportunity member joins (C6)
      sed -i "s#^    - erp/costing@\(.*\)#    - erp/costing@\1\n    - crm/opportunity@${V[crm/opportunity]}#" component.yaml
      sed -i 's#\t"github.com/brickKit/be-sdk-go/v3/component"#\t"github.com/brickKit/be-sdk-go/v3/component"\n\t"github.com/brickKit/crm-opportunity/v3/opportunity"#' members.go
      sed -i 's#costing.Definition())#costing.Definition(), opportunity.Definition())#' members.go
      sed -i 's#、`erp/payment`、`erp/costing`。#、`erp/payment`、`erp/costing`；客户关系成员 `crm/opportunity`。#' BRICKKIT.md
      grep -q '`crm/opportunity`。' BRICKKIT.md && grep -q 'opportunity.Definition()' members.go && grep -q "crm/opportunity@" component.yaml
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
    f=$(mktemp); printf 'be/%s %s: crm/opportunity %s and erp/sales %s (C6 P5, the design without plan references)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "${V[crm/opportunity]}" "${V[erp/sales]}" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到 crm/opportunity %s（设计改成现行的事实，行为不变）、erp/sales %s、erp/billing %s、erp/payment %s。\n' "${V[crm/opportunity]}" "${V[erp/sales]}" "${V[erp/billing]}" "${V[erp/payment]}" > $n
    brickkit release --notes-file $n > $O/release-p5c-$shell.log 2>&1; tail -3 $O/release-p5c-$shell.log
    grep -q "Released" $O/release-p5c-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
