#!/bin/bash
# C8: what sdk-unify leaves by hand for be-sdk-go alpha.128 (made from c1-data/sdk121's tools.sh and probes.sh):
# the Go probe 3.2.57 and its variants, the suite's tag, be-ops alpha.24, be-edge's tests module alpha.10.
# Output: run.out; "TOOLS ALL-DONE" or "TOOLS FAILED <what>".
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c8-data/sdk128-tools
echo $$ > $O/tools.pid
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off SDK=v3.0.0-alpha.128 PYTHONDONTWRITEBYTECODE=1
msg=$(mktemp); notes=$(mktemp)
(
  set -e; cd $R/tools/be-acceptance/probes/go
  sed -i 's/^  version: 3.2.56$/  version: 3.2.57/' component.yaml
  sed -i 's/Version     = "3.2.56"/Version     = "3.2.57"/' probe/defs.go
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy && go vet ./...
  cd .. && python3 variants.py
  cd .. && (. $R/dev/rebuild/experiment-scripts/accenv.sh >/dev/null 2>&1; make check && make probes)
  printf 'The Go probe 3.2.57 on be-sdk-go alpha.128 (C8)\n\nThe probe and its variants move to the SDK the system runs (the notification intents, chapter 18);\nmake check and make probes pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git push -q origin HEAD:main
  printf 'Go 探针 3.2.57：be-sdk-go alpha.128（全系统同一个 SDK 版本，通知意图，线协议第 18 章），探针行为不变。\n' > $notes
  for v in go go2 go3 go4; do (cd probes/$v && brickkit release --notes-file $notes > $O/release-$v.log 2>&1 && grep -q Released $O/release-$v.log); done
  git tag -a v1.0.92 -m "套件 1.0.92：格承载通知组件（NOTIFICATION_INTENT_SOURCES 取格里的流程内核组件），L3 加审批的通知（test_notification.py）；Go 探针 3.2.57（be-sdk-go alpha.128）" && git push -q origin v1.0.92
)
[ $? -eq 0 ] || { echo "TOOLS FAILED probe" >> $O/run.out; exit 1; }
echo "TOOLS probe END" >> $O/run.out
. $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
(
  set -e; cd $R/tools/be-ops
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy && go vet ./...
  go test -race -count=1 ./...
  go test -count=1 -tags integration ./internal/recovery/
  printf 'be-sdk-go alpha.128; release 3.0.0-alpha.24\n\nThe recovery tool moves to the SDK the system runs (C8). Its behaviour does not change. Unit\ntests (-race) and the recovery integration tests pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git tag -a v3.0.0-alpha.24 -m "be-ops 3.0.0-alpha.24：be-sdk-go alpha.128（全系统同一个 SDK 版本），行为不变。"
  git push -q origin HEAD v3.0.0-alpha.24
)
[ $? -eq 0 ] || { echo "TOOLS FAILED be-ops" >> $O/run.out; exit 1; }
echo "TOOLS be-ops END" >> $O/run.out
(
  set -e; cd $R/tools/be-edge/tests
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy
  cd .. && make check && make traefik
  printf 'tests on be-sdk-go alpha.128; release 3.0.0-alpha.10\n\nThe tests module moves to be-sdk-go alpha.128, the version the system runs (C8). The plugin\nitself does not change. make check and make traefik pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git tag -a v3.0.0-alpha.10 -m "be-edge 3.0.0-alpha.10：测试模块换到 be-sdk-go alpha.128，插件不变。"
  git push -q origin HEAD v3.0.0-alpha.10
)
[ $? -eq 0 ] || { echo "TOOLS FAILED be-edge" >> $O/run.out; exit 1; }
echo "TOOLS be-edge END" >> $O/run.out
echo "TOOLS ALL-DONE" >> $O/run.out
