#!/bin/bash
# Which connections to a published Docker port pass through the userland docker-proxy: N HTTP requests from the host's
# loopback, N from a container on another bridge network (the usual case: an app container reaching a database
# published from another compose project), and N from a container on the server's own bridge (hairpin). Prints the
# proxy's CPU ticks for each. Needs Docker with the userland proxy on (the default), nginx:alpine and alpine.
# Usage: docker-proxy-loopback.sh [N] [port]
set -u
N=${1:-300}; PORT=${2:-18999}
docker rm -f dpx-server >/dev/null 2>&1; docker network rm dpx-net >/dev/null 2>&1
docker network create dpx-net >/dev/null
docker run -d --name dpx-server --network dpx-net -p $PORT:80 nginx:alpine >/dev/null
sleep 2
pids=""; for p in $(pgrep -x docker-proxy); do tr '\0' ' ' < /proc/$p/cmdline | grep -q -- "-host-port $PORT " && pids="$pids $p"; done
ticks() { local t=0 x; for p in $pids; do x=$(awk '{print $14+$15}' /proc/$p/stat); t=$((t + x)); done; echo $t; }
from() {  # from <label> <docker run network args...>: N requests from a container
  local label=$1; shift; local t0 t1 ok
  t0=$(ticks)
  ok=$(docker run --rm "$@" --add-host host.docker.internal:host-gateway alpine:latest sh -c \
    "n=0; for i in \$(seq $N); do wget -q -O /dev/null -T 2 http://host.docker.internal:$PORT/ && n=\$((n+1)); done; echo \$n")
  t1=$(ticks); echo "$label, $N requests ($ok ok): proxy ticks +$((t1 - t0))"
}
loop() { local t0 t1 ok=0; t0=$(ticks)
  for i in $(seq $N); do curl -s -o /dev/null --max-time 2 -w '%{http_code}\n' http://127.0.0.1:$PORT/ | grep -q 200 && ok=$((ok+1)); done
  t1=$(ticks); echo "host loopback 127.0.0.1:$PORT, $N requests ($ok ok): proxy ticks +$((t1 - t0))"; }
echo "docker $(docker version -f '{{.Server.Version}}'), proxies for $PORT:$pids, CLK_TCK $(getconf CLK_TCK)"
loop
from "container on the default bridge -> host.docker.internal:$PORT"
from "container on the server's own network (hairpin) -> host.docker.internal:$PORT" --network dpx-net
loop
docker rm -f dpx-server >/dev/null; docker network rm dpx-net >/dev/null
