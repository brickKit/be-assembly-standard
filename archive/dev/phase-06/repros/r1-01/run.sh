#!/usr/bin/env bash
# R1 #1：先用 be-sdk-go 钉的版本跑，再把副本升到当前最新稳定版各跑一次。
# 不需要 Docker：收集器是进程内的 httptest。
set -euo pipefail
cd "$(dirname "$0")"
echo "== pinned (be-sdk-go go.mod)"
go list -m go.opentelemetry.io/otel go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc google.golang.org/grpc
go run .

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp main.go go.mod go.sum "$tmp/"
cd "$tmp"
go get go.opentelemetry.io/otel@latest go.opentelemetry.io/otel/sdk@latest go.opentelemetry.io/otel/sdk/metric@latest \
  go.opentelemetry.io/otel/trace@latest go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp@latest \
  go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc@latest google.golang.org/grpc@latest 2>&1 | grep -v "^go: \(downloading\|upgraded\|added\)" || true
go mod tidy >/dev/null
echo "== latest"
go list -m go.opentelemetry.io/otel go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc google.golang.org/grpc
go run .
