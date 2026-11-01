#!/bin/bash
# Step 13: the requests each container, pod or process of a cell served, from its saved log (one <name>.log per unit,
# as runner13.sh saves them before the cell goes down: retro-step12.md I3). "access" counts every request; "user"
# those whose route starts with /api (the user surface, through the front door); "grpc" the system-surface calls from
# the other components over the project network (their access line names the gRPC method, "/pkg.Service/Method").
# Usage: replica-counts.sh <logs directory> <out file>
D=$1; OUT=$2
{ echo "# $(date -Is) from $D"
  for f in "$D"/*.log; do
    a=$(grep -c '"msg":"access"' "$f"); u=$(grep '"msg":"access"' "$f" | grep -c '"route":"/api')
    g=$(grep '"msg":"access"' "$f" | grep -c '"method":"/')
    echo "$(basename "$f" .log): access=$a user-surface=$u grpc=$g"
  done; } > "$OUT"
cat "$OUT"
