#!/bin/bash
# Step 12, G6: does a ProcessPoolExecutor worker run the program's entry again? app/__main__.py has no
# `if __name__ == "__main__"` guard and prints one line per run; CHILD_GUARD stops a re-run from starting a pool itself.
# Run as `python -m app` (a package entry, as a Python shell starts) and as `python entry.py` (a script path), under the
# default start method and each explicit one. Usage: run.sh [python]   (writes nothing; copy the output)
set -u
PY=${1:-python3.14}; cd "$(dirname "$0")"; cp app/__main__.py entry.py
echo "$($PY --version); default start method: $($PY -c 'import multiprocessing as m; print(m.get_start_method())')"
for m in "" forkserver spawn fork; do echo "== $PY -m app ${m:-(default)}"; $PY -m app $m 2>&1 | grep -E 'ENTRY|result|Error'; done
for m in "" spawn fork; do echo "== $PY entry.py ${m:-(default)}"; $PY entry.py $m 2>&1 | grep -E 'ENTRY|result|Error'; done
rm -f entry.py
