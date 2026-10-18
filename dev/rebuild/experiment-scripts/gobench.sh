#!/bin/bash
# The Go SDK benchmarks on main and on perf/httpx (5 runs each), CPU profiles of main, and the top functions.
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad
G=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-go
OUT=$S/prof/gobench; rm -rf "${OUT:?}"; mkdir -p $OUT
cd $G
for branch in main perf/httpx; do
  git checkout -q $branch
  name=${branch//\//-}
  go test -run '^$' -bench . -benchmem -count 5 ./grpcx/ > $OUT/bench-$name.txt 2>&1
  echo "{\"bench\": \"$name\", \"exit\": $?}" >> $OUT/results.jsonl
done
git checkout -q main
for b in UserSurfaceRequest SystemCallOverMTLS UserSurfaceThenSystemCall; do
  go test -run '^$' -bench "^Benchmark$b\$" -benchtime 5s -cpuprofile $OUT/cpu-$b.out -o $OUT/grpcx.test ./grpcx/ > /dev/null 2>&1
  go tool pprof -top -nodecount 40 $OUT/grpcx.test $OUT/cpu-$b.out > $OUT/top-$b.txt 2>&1
done
echo DONE >> $OUT/results.jsonl
