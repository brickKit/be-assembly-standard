#!/usr/bin/env bash
# Keep a cell's logs before it goes down (the logs go with it): every container's or pod's log on the cell's own engine,
# the requests each replica served (replica-counts.sh), and the large logs packed (a suite E cell is about 160 MB as
# text, 15 MB packed). Every runner calls this before `down`; stopping a cell by hand, run it first too: step 13's
# first D13-E1 smoke went down unsaved and its per-replica counts had to be copied from the terminal (retro-step13.md Q7).
# Usage: cell-logs.sh <cell dir> <out dir> [row]   (the row defaults to the cell.yaml's)
set -u
D=$1 O=$2 ROW=${3:-$(sed -n 's/^row: *//p' "$1/cell.yaml")}
X=$(cd "$(dirname "$0")" && pwd)
ns=$(basename "$D"); ns=${ns,,}
mkdir -p "$O"
case $ROW in
  K) for p in $(kubectl --context bek -n "$ns" get pods -o name 2>/dev/null); do
       kubectl --context bek -n "$ns" logs "$p" --all-containers > "$O/${p#pod/}.log" 2>&1; done ;;
  P|LP) for n in $(podman ps -a --filter "label=com.docker.compose.project=brickkit-$ns" --format '{{.Names}}'); do
       podman logs "$n" > "$O/$n.log" 2>&1; done ;;
  *) for n in $(docker ps -a --filter "label=com.docker.compose.project=brickkit-$ns" --format '{{.Names}}'); do
       docker logs "$n" > "$O/$n.log" 2>&1; done ;;
esac
bash "$X/replica-counts.sh" "$O" "$O/../replica-counts.txt" > /dev/null
find "$O" -name '*.log' -size +256k -exec gzip -9f {} +
