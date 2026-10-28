#!/bin/bash
# Step 10, B6 (step10-plan.md 4.2): rootless against rootful Podman, one batch, Docker left running with the base
# resources (as for every row). rootful/setup.sh (run once by the maintainer) opens root's podman.socket to group docker
# and lets Podman's bridges through Docker's FORWARD policy; runner9.sh sends the cells marked `podman: rootful` there.
# Rootless and rootful next to each other: P9-S, P9-S-root, P9-H, P9-H-root. Same flow and load as step 9. About 3.7 h.
# Usage: night10d.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
echo "NIGHT START $(date -Is)" >> "$OUT/night.log"
CONTAINER_HOST=unix:///run/podman/podman.sock podman info --format '{{.Host.Security.Rootless}}' 2>&1 | grep -qx false \
  || { echo "NIGHT ABORT rootful Podman not reachable: run rootful/setup.sh" >> "$OUT/night.log"; exit 1; }
"$X/runner9.sh" "$OUT/b6" P9-S P9-S-root P9-H P9-H-root
echo "NIGHT b6 done exit=$? $(date -Is)" >> "$OUT/night.log"
echo "NIGHT ALL-DONE $(date -Is)" >> "$OUT/night.log"
