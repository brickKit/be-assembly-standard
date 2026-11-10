#!/bin/bash
# C1 E0b: the Go shells on the members released for mdm/org 3.0.34 (positions) and its dependency cascade:
# version up, members, go get, tidy, vet, tests, commit, push, brickkit release. Output in shells.log; "SHELLS ALL-DONE" or "SHELLS FAILED <shell>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/shells.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod
declare -A V=([mdm/org]=3.0.34 [mdm/partner]=3.0.37 [mdm/product]=3.0.36 [erp/inventory]=3.0.35 [erp/credit]=3.0.35
  [erp/sales]=3.0.44 [erp/billing]=3.0.53)
SDK=v3.0.0-alpha.119; declare -A NEWV=([go-infra]=3.0.72 [go-core]=3.0.80)
for shell in go-infra go-core; do
  d=$R/shell/be/$shell; old=$(sed -n 's/^  version: //p' $d/component.yaml); NEW=${NEWV[$shell]}
  echo "SHELLS $shell BEGIN $old -> $NEW"
  (
    set -e; cd $d
    sed -i "s/^  version: $old/  version: $NEW/" component.yaml
    sed -i "s/Version = \"$old\"/Version = \"$NEW\"/" main.go
    mods="github.com/brickKit/be-sdk-go/v3@$SDK"
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
    f=$(mktemp); printf 'be/%s %s: members released for mdm/org 3.0.34 (positions)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$shell" "$NEW" > $f
    git commit -q -F $f && git log -1 --format='%h %s'
    git push -q
    n=$(mktemp); printf '成员换到 mdm/org 3.0.34（部门里的岗位）与随它连锁发布的版本，行为不变。\n' > $n
    brickkit release --notes-file $n > $O/release-$shell.log 2>&1; tail -3 $O/release-$shell.log
    grep -q "Released" $O/release-$shell.log
  ) || { echo "SHELLS FAILED $shell"; exit 1; }
  echo "SHELLS $shell END $NEW"
done
echo "SHELLS ALL-DONE"
