#!/bin/bash
# Go 1.27.2 PGO: one CPU profile of all three request benchmarks (5 s each, merged), then the benchmarks built with
# -pgo=off and with that profile, 5 runs each, interleaved off/on to spread machine drift.
S=<scratch>
G=<repo>/tools/be-sdk-go
OUT=$S/prof/pgo; cd $G
for b in UserSurfaceRequest SystemCallOverMTLS UserSurfaceThenSystemCall; do
  go test -run '^$' -bench "^Benchmark$b\$" -benchtime 5s -cpuprofile $OUT/prof-$b.out ./grpcx/ > /dev/null 2>&1
done
go tool pprof -proto $OUT/prof-*.out > $OUT/merged.pgo 2>/dev/null
rm -f $OUT/bench-off.txt $OUT/bench-on.txt
for i in 1 2 3 4 5; do
  go test -run '^$' -bench . -benchmem -count 1 -pgo=off ./grpcx/ >> $OUT/bench-off.txt 2>&1
  go test -run '^$' -bench . -benchmem -count 1 -pgo=$OUT/merged.pgo ./grpcx/ >> $OUT/bench-on.txt 2>&1
done
echo DONE > $OUT/done
