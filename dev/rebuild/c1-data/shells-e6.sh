#!/bin/bash
# C1 E6: the Go shells on be-sdk-go alpha.121 and the members released by its unify (sdk121/), the Go probe 3.2.52, and
# mdm/employee compiled into be/go-infra: version up, members, go get, tidy, vet, tests, commit, push, brickkit release.
# Output in shells-e6.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells-e6.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
declare -A V=([infra/audit]=3.0.38 [infra/authz]=3.0.47 [infra/iam-casdoor]=3.0.43 [mdm/currency]=3.0.33 [mdm/org]=3.0.35
  [mdm/employee]=3.0.2 [mdm/partner]=3.0.38 [mdm/product]=3.0.37 [erp/credit]=3.0.36 [erp/inventory]=3.0.36
  [erp/sales]=3.0.45 [erp/billing]=3.0.54)
PROBE=3.2.52; SDK=v3.0.0-alpha.121; declare -A NEWV=([go-infra]=3.0.74 [go-core]=3.0.81)
# SHELLS (default both): the shells to do; go-infra alone redid 3.0.73 as 3.0.74 (see the end of this file)
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
    f=$(mktemp); printf 'be/%s %s: be-sdk-go alpha.121 and the members released on it%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" "$([ $shell = go-infra ] && echo '; mdm/employee joins')" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到 be-sdk-go alpha.121 与在它上面发布的版本（全系统同一个 SDK 版本）%s。\n' "$([ $shell = go-infra ] && echo '；编进员工组件 mdm/employee')" > $n
    brickkit release --notes-file $n > $O/release-e6-$shell.log 2>&1; tail -3 $O/release-e6-$shell.log
    grep -q "Released" $O/release-e6-$shell.log
  )
  # the subshell's status is read as its own statement: inside "( ... ) || ..." bash ignores set -e, and the first run
  # released be/go-infra 3.0.73 after its go get and tests had failed
  [ $? -eq 0 ] || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
# 3.0.73 (2026-11-10): released broken by the bug above: mdm/employee 3.0.1 had only its bare tag (no
# release.goModule), go get failed and fell back to a pseudo-version, TestMembersMatchTheManifest failed. Never used.
