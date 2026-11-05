#!/bin/bash
# F3-X again once the public Go proxy serves mdm-partner v3.0.19 (it had cached a failure of its own to resolve
# github.com: 404 on .info): poll it every minute for an hour, then the cell from an empty database, then down.
R=/home/zhijie/Desktop/github/be-assembly-standard; O=$(dirname "$(realpath "$0")")
for i in $(seq 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' 'https://proxy.golang.org/github.com/brick!kit/mdm-partner/v3/@v/v3.0.19.info')
  echo "$(date -Is) proxy $code" >> $O/proxy-wait.log
  [ "$code" = 200 ] && break
  sleep 60
done
KEEP_UP=0 bash $R/dev/rebuild/experiment-scripts/cell-chain.sh F3-X $O/F3-X > $O/F3-X.log 2>&1
echo "F3-X rc=$?" >> $O/summary-x.txt
(cd $R/dev/rebuild/experiment-cells/F3-X && brickkit down > /dev/null 2>&1)
echo done >> $O/summary-x.txt
