#!/bin/bash
# C5 P0b: be/go-core on erp/inventory 3.0.39 (movements by valuation sequence), erp/finance 3.0.5 (the cost rules)
# and their cascade. Made from c3-data/shells-p5e.sh. Output in shells-p0b.log;
# "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-p0b.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V=([infra/audit]=3.0.38 [infra/authz]=3.0.48 [infra/iam-casdoor]=3.0.47 [mdm/currency]=3.0.33 [mdm/org]=3.0.35
  [mdm/employee]=3.0.3 [mdm/partner]=3.0.40 [mdm/product]=3.0.38 [erp/credit]=3.0.38 [erp/inventory]=3.0.39
  [erp/sales]=3.0.49 [erp/billing]=3.0.58 [erp/purchase]=3.0.3 [erp/finance]=3.0.5 [erp/payment]=3.0.4)
PROBE=3.2.52; SDK=v3.0.0-alpha.121; declare -A NEWV=([go-infra]=none [go-core]=3.0.93)
# SHELLS (default both): the shells to do
for shell in ${SHELLS:-go-core}; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${NEWV[$shell]}
  echo "SHELLS $shell BEGIN $old -> $NEW"
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
    f=$(mktemp); printf 'be/%s %s: erp/inventory 3.0.39 and erp/finance 3.0.5 with their cascade (C5 P0b)%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到 erp/inventory 3.0.39（按计价序号读流水）、erp/finance 3.0.5（成本的规则键）及连锁的 erp/purchase 3.0.3、erp/sales 3.0.49、erp/billing 3.0.58、erp/payment 3.0.4%s。\n' "" > $n
    brickkit release --notes-file $n > $O/release-p0b-$shell.log 2>&1; tail -3 $O/release-p0b-$shell.log
    grep -q "Released" $O/release-p0b-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e, and the first run
  # released be/go-infra 3.0.73 after its go get and tests had failed
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
