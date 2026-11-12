#!/bin/bash
# C7 P7: what sdk-unify leaves by hand for be-sdk-go alpha.126 (made from c1-data/sdk121's tools.sh and probes.sh):
# the Go probe 3.2.55 and its variants, the suite's tag, be-ops alpha.22, be-edge's tests module alpha.8.
# Output: run.out; "TOOLS ALL-DONE" or "TOOLS FAILED <what>".
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c7-data/p7-sdk126
echo $$ > $O/tools.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off SDK=v3.0.0-alpha.126 PYTHONDONTWRITEBYTECODE=1
msg=$(mktemp); notes=$(mktemp)
(
  set -e; cd $R/tools/be-acceptance/probes/go
  sed -i 's/^  version: 3.2.54$/  version: 3.2.55/' component.yaml
  sed -i 's/Version     = "3.2.54"/Version     = "3.2.55"/' probe/defs.go
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy && go vet ./...
  cd .. && python3 variants.py
  cd .. && (. $R/dev/rebuild/experiment-scripts/accenv.sh >/dev/null 2>&1; make check && make probes)
  printf 'The Go probe 3.2.55 on be-sdk-go alpha.126; the approvals in the cells (C7 P7)\n\nThe probe and its variants move to the SDK the system runs; make check and make probes pass.\nThe cells place infra/workflow (its ports, the bus, WORKFLOW_TASK_SOURCES from the placed flow\nmanagers) and know its resources; L3 test_workflow.py (a requisition approved from the worklist, a\nbank charge rejected then posted); test_payment.py expects SELF_APPROVAL.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git push -q origin HEAD:main
  printf 'Go 探针 3.2.55：be-sdk-go alpha.126（全系统同一个 SDK 版本，流程内核在员工投影变化后立即重新解析），探针行为不变。\n' > $notes
  for v in go go2 go3 go4; do (cd probes/$v && brickkit release --notes-file $notes > $O/release-$v.log 2>&1 && grep -q Released $O/release-$v.log); done
  git tag -a v1.0.87 -m "套件 1.0.87：Go 探针 3.2.55（be-sdk-go alpha.126）；格承载统一待办，L3 加审批与待办的场景" && git push -q origin v1.0.87
)
[ $? -eq 0 ] || { echo "TOOLS FAILED probe" >> $O/run.out; exit 1; }
echo "TOOLS probe END" >> $O/run.out
. $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
(
  set -e; cd $R/tools/be-ops
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy && go vet ./...
  go test -race -count=1 ./...
  go test -count=1 -tags integration ./internal/recovery/
  printf 'be-sdk-go alpha.126; release 3.0.0-alpha.22\n\nThe recovery tool moves to the SDK the system runs (C7 P7). Its behaviour does not change. Unit\ntests (-race) and the recovery integration tests pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git tag -a v3.0.0-alpha.22 -m "be-ops 3.0.0-alpha.22：be-sdk-go alpha.126（全系统同一个 SDK 版本），行为不变。"
  git push -q origin HEAD v3.0.0-alpha.22
)
[ $? -eq 0 ] || { echo "TOOLS FAILED be-ops" >> $O/run.out; exit 1; }
echo "TOOLS be-ops END" >> $O/run.out
(
  set -e; cd $R/tools/be-edge/tests
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy
  cd .. && make check && make traefik
  printf 'tests on be-sdk-go alpha.126; release 3.0.0-alpha.8\n\nThe tests module moves to be-sdk-go alpha.126, the version the system runs (C7 P7). The plugin\nitself does not change. make check and make traefik pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git tag -a v3.0.0-alpha.8 -m "be-edge 3.0.0-alpha.8：测试模块换到 be-sdk-go alpha.126，插件不变。"
  git push -q origin HEAD v3.0.0-alpha.8
)
[ $? -eq 0 ] || { echo "TOOLS FAILED be-edge" >> $O/run.out; exit 1; }
echo "TOOLS be-edge END" >> $O/run.out
echo "TOOLS ALL-DONE" >> $O/run.out
