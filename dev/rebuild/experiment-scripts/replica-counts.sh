#!/bin/bash
# Step 13: the requests each replica of a cell served, from the containers' logs, written straight to a file (the
# containers go with `brickkit down`, retro-step12.md I3). "access" counts every request; "user" those whose route
# starts with /api (the user surface, through the front door); "grpc" the system-surface calls from the other components
# over the project network (their access line names the gRPC method, "/pkg.Service/Method").
# Usage: replica-counts.sh <project, e.g. d13-e1> <out file> [docker|podman]
P=$1; OUT=$2; E=${3:-docker}
{ echo "# $(date -Is) project $P on $E"
  for c in $($E ps --format '{{.Names}}' | grep "^brickkit-$P-.*-[0-9]*$" | sort); do
    l=$($E logs "$c" 2>&1)
    a=$(grep -c '"msg":"access"' <<<"$l"); u=$(grep '"msg":"access"' <<<"$l" | grep -c '"route":"/api')
    g=$(grep '"msg":"access"' <<<"$l" | grep -c '"method":"/')
    echo "$c: access=$a user-surface=$u grpc=$g"
    base=${c%-[0-9]*}
    if $E ps --format '{{.Names}}' | grep -q "^$base-2$"; then
      mkdir -p "$OUT.access"; grep '"msg":"access"' <<<"$l" > "$OUT.access/$c.log"
    fi
  done; } > "$OUT"
cat "$OUT"
