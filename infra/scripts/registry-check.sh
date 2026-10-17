#!/usr/bin/env bash
# Consistency check of registry/ports.tsv and registry/schemas.tsv. The old check in be-ops counted the 62 components of
# the old catalogue; the rules that still hold live in registry_check.py (be-ops is not touched, experiment step 1).
set -uo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/registry_check.py"
