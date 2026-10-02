#!/usr/bin/env bash
# r1-03: grpc-js + ts-proto with the local Node 24 (type stripping, no build step); grpcio check in a throwaway container.
set -euo pipefail
cd "$(dirname "$0")"
npm ci --silent
# regenerate the ts-proto code (protoc ships with the grpc-tools package)
node_modules/grpc-tools/bin/protoc --plugin=protoc-gen-ts_proto=node_modules/.bin/protoc-gen-ts_proto --ts_proto_out=gen \
  --ts_proto_opt=outputServices=grpc-js,esModuleInterop=true,outputSchema=true,importSuffix=.ts -Iproto proto/echo.proto
node repro.ts
GRPC_TRACE=resolving_load_balancer,dns_resolver GRPC_VERBOSITY=DEBUG node throttle.ts 2> throttle-trace.log
docker run --rm -v "$PWD/py:/w:ro" python:3.13-slim \
  sh -c "pip install -q --root-user-action=ignore grpcio==1.76.0 2>/dev/null && python /w/throttle_check.py"
