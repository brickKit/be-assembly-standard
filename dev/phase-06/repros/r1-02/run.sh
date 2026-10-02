#!/usr/bin/env bash
# R1 #2：先用 be-sdk-go 钉的 grpc-go 跑，再在副本里升到最新稳定版跑一次。约 1.5 分钟（T13 要等 dns 解析器的 30 s 间隔）。
set -euo pipefail
cd "$(dirname "$0")"
echo "== pinned"; go list -m google.golang.org/grpc
go run .
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp main.go repro.proto go.mod go.sum "$tmp/"; cd "$tmp"
go get google.golang.org/grpc@latest 2>&1 | grep -v "^go: \(downloading\|upgraded\|added\)" || true
go mod tidy >/dev/null
echo "== latest"; go list -m google.golang.org/grpc
go run .
