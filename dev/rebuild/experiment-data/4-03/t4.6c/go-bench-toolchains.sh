#!/bin/bash
# The same SDK code (main) benchmarked on Go 1.26.8 (a worktree with go.mod back at 1.26) and Go 1.27.2, 5 runs each,
# one after the other, plus a CPU profile of the user-surface request on 1.27.2.
S=<scratch>
G=<repo>/tools/be-sdk-go
OUT=$S/prof/gobench127; rm -rf "${OUT:?}"; mkdir -p $OUT
W=$S/wt-go126; git -C $G worktree remove --force $W 2>/dev/null; git -C $G worktree add -q --detach $W HEAD
(cd $W && /usr/bin/go mod edit -go=1.26.0 -toolchain=none && GOTOOLCHAIN=local /usr/bin/go version > $OUT/version-126.txt &&
  GOTOOLCHAIN=local /usr/bin/go test -run '^$' -bench . -benchmem -count 5 ./grpcx/ > $OUT/bench-126.txt 2>&1)
echo "{\"bench\": \"go1.26\", \"exit\": $?}" >> $OUT/results.jsonl
git -C $G worktree remove --force $W
(cd $G && go version > $OUT/version-127.txt && go test -run '^$' -bench . -benchmem -count 5 ./grpcx/ > $OUT/bench-127.txt 2>&1)
echo "{\"bench\": \"go1.27\", \"exit\": $?}" >> $OUT/results.jsonl
(cd $G && go test -run '^$' -bench '^BenchmarkUserSurfaceRequest$' -benchtime 5s -cpuprofile $OUT/cpu-user.out -o $OUT/grpcx.test ./grpcx/ > /dev/null 2>&1 &&
  go tool pprof -top -cum -nodecount 60 $OUT/grpcx.test $OUT/cpu-user.out > $OUT/top-user.txt 2>&1)
echo DONE >> $OUT/results.jsonl
