#!/bin/bash
# C7 P6: the seeds of the approvals: mdm/employee 3.0.7 (links the two leads), infra/workflow 3.0.1 (its seed),
# erp/purchase 3.0.9 (the employee pin), erp/payment 3.0.13 (the employee pin, its seed). Output in release-p6.log;
# "P6 ALL-DONE" or "P6 FAILED <id>".
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c7-data
echo $$ > $O/release-p6.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off PYTHONDONTWRITEBYTECODE=1
. $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
. $R/dev/rebuild/experiment-scripts/iamenv.sh >/dev/null 2>&1
rel() { # id dir old new constfile line subject notes
  local id=$1 d=$2 old=$3 new=$4 cf=$5 line=$6 subject=$7 notes=$8
  echo "P6 $id BEGIN $old -> $new"
  (
    set -e; cd $d
    sed -i "s/^  version: $old\$/  version: $new/" component.yaml
    sed -i "s/Version  = \"$old\"/Version  = \"$new\"/" $cf
    grep -q "version: $new" component.yaml && grep -q "\"$new\"" $cf
    python3 - "$line" <<'PY'
import sys,re
p='docs/design.md'; s=open(p).read()
m=re.search(r'^3\.0\.\d+(：|（)', s, re.M)
s=s[:m.start()]+sys.argv[1]+'\n\n'+s[m.start():]
open(p,'w').write(s)
PY
    sed -i -E "s#    - id: mdm/employee@[0-9.]+#    - id: mdm/employee@3.0.7#" component.yaml
    go mod tidy && gofmt -l . | (! grep .) && go vet ./... && go test -count=1 ./...
    go test -count=1 -p 1 -tags integration ./...
    brickkit lint
    f=$(mktemp); printf '%s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' "$subject" > $f
    git add -A && git commit -q -F $f && git push -q
    n=$(mktemp); printf '%s\n' "$notes" > $n
    brickkit release --notes-file $n > $O/release-p6-${id//\//-}.log 2>&1; tail -2 $O/release-p6-${id//\//-}.log
    grep -q Released $O/release-p6-${id//\//-}.log
  )
  [ $? -eq 0 ] || { echo "P6 FAILED $id"; exit 1; }
  echo "P6 $id END $new"
}
C=$R/components
rel mdm/employee $C/mdm/employee 3.0.6 3.0.7 employee/definition.go \
  '3.0.7：{version}：只改种子：`test.buyer.lead`、`test.finance.lead` 关联到 CN01 的采购部、财务部负责人（`PUR-MGR`、`FIN-MGR`），采购与付款按岗位审批靠它们（装配项目阶段计划 C7 的 P6）；行为不变。' \
  '3.0.7: the seed links the purchasing and finance leads (C7 P6)' \
  '只改种子：test.buyer.lead、test.finance.lead 关联到 CN01 的采购部、财务部负责人（PUR-MGR、FIN-MGR），采购与付款按岗位审批靠它们；行为不变。'
rel infra/workflow $C/infra/workflow 3.0.0 3.0.1 workflow/definition.go \
  '3.0.1：{version}：加了种子（`cmd/seed`：“待办维护”给种子用户，“我的待办”给采购与财务的审批人、采购员与出纳；装配项目阶段计划 C7 的 P6）；行为不变。' \
  '3.0.1: the seed grants the worklist (C7 P6)' \
  '加了种子：“待办维护”给种子用户，“我的待办”给采购与财务的审批人、采购员与出纳；行为不变。'
rel erp/purchase $C/erp/purchase 3.0.8 3.0.9 purchase/definition.go \
  '3.0.9：{version}：可选依赖 mdm/employee 跟到 3.0.7（它的种子关联了审批人，装配项目阶段计划 C7 的 P6）；行为不变。' \
  '3.0.9: mdm/employee 3.0.7 (C7 P6)' \
  '可选依赖 mdm/employee 跟到 3.0.7（它的种子关联了审批人）；行为不变。'
rel erp/payment $C/erp/payment 3.0.12 3.0.13 payment/definition.go \
  '3.0.13：{version}：种子的付款政策：CN01 按岗位 `FIN-MGR`，ES01、US01 按 `test.finance.lead` 本人（员工只在自己的法人任职）；可选依赖 mdm/employee 跟到 3.0.7（装配项目阶段计划 C7 的 P6）；行为不变。' \
  '3.0.13: the seed'"'"'s payment policies; mdm/employee 3.0.7 (C7 P6)' \
  '种子的付款政策：CN01 按岗位 FIN-MGR，ES01、US01 按 test.finance.lead 本人；可选依赖 mdm/employee 跟到 3.0.7；行为不变。'
echo "P6 ALL-DONE"
