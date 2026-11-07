#!/usr/bin/env bash
# Runs every test of the parent repository's scripts (this directory), each the way it is written: pytest files
# with pytest, the self-running Python files (they have a __main__) with python3, the .sh files with bash.
# One line per file; exits 1 when any fails, or when it finds no test at all (the check would then check nothing).
# Usage: bash infra/scripts/tests/run-all.sh      (make scripts-test; part of make gates)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
export PYTHONDONTWRITEBYTECODE=1
n=0 failed=()
for t in test_*; do
  [ -f "$t" ] || continue
  case $t in
    *.py) if grep -q '^if __name__ == "__main__":' "$t"; then cmd=(python3 "$t")
          else cmd=(python3 -m pytest -q -p no:cacheprovider "$t"); fi ;;
    *.sh) cmd=(bash "$t") ;;
    *) continue ;;
  esac
  n=$((n + 1))
  log="$(mktemp)"
  if timeout 300 "${cmd[@]}" > "$log" 2>&1; then
    echo "  ok   $t"
  else
    echo "  FAIL $t"; tail -20 "$log" | sed 's/^/       /'; failed+=("$t")
  fi
  rm -f "$log"
done
[ "$n" -gt 0 ] || { echo "no script tests found in $(pwd)"; exit 1; }
echo "scripts-test: $((n - ${#failed[@]}))/$n files pass"
[ ${#failed[@]} -eq 0 ]
