#!/bin/bash
# The dependency footprint of each library: a minimal program importing only its writing package, go mod tidy, then
# the modules, the packages and the binary size. Output: footprint.txt.
set -eu
O=$(dirname "$(realpath "$0")"); W=$(mktemp -d)
for m in "github.com/parquet-go/parquet-go@v0.32.0 github.com/parquet-go/parquet-go" \
         "github.com/apache/arrow-go/v18@v18.8.0 github.com/apache/arrow-go/v18/parquet/pqarrow"; do
  set -- $m; d=$(mktemp -d -p $W)
  (cd $d && printf 'module x\n\ngo 1.27.0\n' > go.mod && printf 'package main\nimport _ "%s"\nfunc main(){}\n' $2 > m.go \
    && GOFLAGS=-mod=mod go get $1 >/dev/null 2>&1 && go mod tidy >/dev/null 2>&1 && go build -o b . \
    && echo "$2 ($1): modules $(go list -m all | tail -n +2 | wc -l), packages $(go list -deps . | grep -c '\.'), binary $(du -k b | cut -f1) KiB")
done > $O/footprint.txt
echo "# $(go version)" >> $O/footprint.txt
