#!/bin/bash
# C7 P3: be-sdk-go 3.0.0-alpha.122 (the flow kernel), the whole integration suite before the release.
O=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/c7-data/sdk-it; echo $$ > $O/pid
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-go
source ../../dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1
export GOPROXY=direct GONOSUMDB='github.com/brickKit/*' GOFLAGS=-mod=mod GOWORK=off
make test-integration > $O/test.log 2>&1; rc=$?
echo "SDK-IT DONE exit=$rc" >> $O/run.out
