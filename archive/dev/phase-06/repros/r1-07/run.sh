#!/usr/bin/env bash
# r1-07: run the three clients against throwaway NATS servers (JetStream on).
# Containers (see README): r1-r1b-nats (2.10), r1-r1b-nats211 (2.11), r1-r1b-nats212 (2.12).
set -euo pipefail
cd "$(dirname "$0")"
url() { echo "nats://127.0.0.1:$(docker port "$1" 4222/tcp | head -1 | sed 's/.*://')"; }
N210=$(url r1-r1b-nats)
# nats.go against all three server lines
(cd go && for c in r1-r1b-nats r1-r1b-nats211 r1-r1b-nats212; do NATS_URL=$(url $c) go run .; done)
# nats-py: the version be-sdk-python pins today, and the latest
for v in 2.11.0 2.16.0; do
  docker run --rm --network host -e NATS_URL="$N210" -v "$PWD/py:/w:ro" python:3.13-slim \
    sh -c "pip install -q --root-user-action=ignore nats-py==$v 2>/dev/null && python /w/repro.py"
done
# nats.js v3 with the local Node 24
(cd js && npm ci --silent && NATS_URL="$N210" node repro.mjs)
