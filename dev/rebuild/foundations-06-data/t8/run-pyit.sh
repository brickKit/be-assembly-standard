#!/bin/bash
# T8: be-sdk-python a57 integration tests, output in pyit.log.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
echo $$ > $O/pyit.pid
set -a; . $R/dev/rebuild/experiment-scripts/itenv.sh >/dev/null 2>&1; set +a
cd $R/tools/be-sdk-python
PYTHONDONTWRITEBYTECODE=1 uv run pytest -q -m integration -p no:cacheprovider > $O/pyit.log 2>&1
echo "PYIT EXIT $?" >> $O/pyit.log
