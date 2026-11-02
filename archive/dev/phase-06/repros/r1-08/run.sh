#!/usr/bin/env bash
# r1-08: Fastify 5 multi-instance check with the local Node 24. No containers needed.
set -euo pipefail
cd "$(dirname "$0")"
npm ci --silent
node repro.mjs
