#!/bin/bash
# C1 E6: the tools on be-sdk-go alpha.121 (pin-check's last two): be-ops (unit tests -race, the recovery integration
# tests; v3.0.0-alpha.19) and be-edge's tests module (make check, make traefik; v3.0.0-alpha.5). Output: tools.out;
# "TOOLS ALL-DONE" or "TOOLS FAILED <tool>".
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$R/dev/rebuild/c1-data/sdk121
echo $$ > $O/tools.pid
. $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off SDK=v3.0.0-alpha.121
msg=$(mktemp)
(
  set -e; cd $R/tools/be-ops
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy && go vet ./...
  go test -race -count=1 ./...
  go test -count=1 -tags integration ./internal/recovery/
  printf 'be-sdk-go alpha.121; release 3.0.0-alpha.19\n\nThe recovery tool moves to the SDK the system runs (C1 E6). Its behaviour does not change. Unit\ntests (-race) and the recovery integration tests pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git tag -a v3.0.0-alpha.19 -m "be-ops 3.0.0-alpha.19：be-sdk-go alpha.121（全系统同一个 SDK 版本），行为不变。"
  git push -q origin HEAD v3.0.0-alpha.19
)
[ $? -eq 0 ] || { echo "TOOLS FAILED be-ops"; exit 1; }
echo "TOOLS be-ops END"
(
  set -e; cd $R/tools/be-edge/tests
  go get github.com/brickKit/be-sdk-go/v3@$SDK && go mod tidy
  cd .. && make check && make traefik
  printf 'tests on be-sdk-go alpha.121; release 3.0.0-alpha.5\n\nThe tests module moves to be-sdk-go alpha.121, the version the system runs (C1 E6). The plugin\nitself does not change. make check and make traefik pass.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n' > $msg
  git add -A && git commit -q -F $msg && git tag -a v3.0.0-alpha.5 -m "be-edge 3.0.0-alpha.5：测试模块换到 be-sdk-go alpha.121，插件不变。"
  git push -q origin HEAD v3.0.0-alpha.5
)
[ $? -eq 0 ] || { echo "TOOLS FAILED be-edge"; exit 1; }
echo "TOOLS be-edge END"
echo "TOOLS ALL-DONE"
