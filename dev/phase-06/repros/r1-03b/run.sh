#!/usr/bin/env bash
# r1-03b: is (be.v1.max_items) readable at runtime? ts-proto + grpc-js with the local Node 24;
# Python grpcio/protobuf in a throwaway python:3.13-slim container.
set -euo pipefail
cd "$(dirname "$0")"
BEP=../../../../tools/be-protocol/proto        # the real be/v1/limits.proto
npm ci --silent
rm -rf gen && mkdir gen
node_modules/grpc-tools/bin/protoc --plugin=protoc-gen-ts_proto=node_modules/.bin/protoc-gen-ts_proto --ts_proto_out=gen \
  --ts_proto_opt=outputServices=grpc-js,esModuleInterop=true,outputSchema=true,importSuffix=.ts,enumsAsLiterals=true -Iproto -I"$BEP" proto/batch.proto
node repro.ts
docker run --rm -v "$PWD/proto:/w/proto:ro" -v "$PWD/py:/w/py:ro" -v "$(realpath "$BEP"):/w/bep:ro" python:3.13-slim sh -c '
  pip install -q --root-user-action=ignore grpcio==1.76.0 grpcio-tools==1.76.0 2>/dev/null &&
  mkdir -p /tmp/gen && python -m grpc_tools.protoc -I/w/proto -I/w/bep --python_out=/tmp/gen --grpc_python_out=/tmp/gen /w/proto/batch.proto /w/bep/be/v1/limits.proto &&
  PYTHONPATH=/tmp/gen python /w/py/check.py'
