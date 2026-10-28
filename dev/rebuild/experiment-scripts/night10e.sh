#!/bin/bash
# Step 10, B7 (step10-plan.md 5.4): the base resources outside against inside the K row's cluster, one batch.
# K9-X with Docker's base resources first (the reference); then Casdoor's schema dumped, Docker's base resources
# stopped, the same four started in the cluster (base-cluster/base-cluster.sh), K9-X-cb, the cluster's taken down and
# Docker's started again. The node stays up between the two (KEEP_CLUSTER) and stops at the end. About 2 hours.
# Usage: night10e.sh <out>   (CONF: a snapshot of the conformance tools; run it under systemd-inhibit)
set -u
OUT=$(realpath -m "$1"); X=/home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-scripts
B=$X/base-cluster/base-cluster.sh
mkdir -p "$OUT"; echo $$ > "$OUT/night.pid"
log() { echo "NIGHT $* $(date -Is)" >> "$OUT/night.log"; }
log START
KEEP_CLUSTER=1 "$X/runner9.sh" "$OUT/b7" K9-X; log "outside done exit=$?"
# whatever happens below, Docker's base resources come back and the node stops
restore() { "$B" down >> "$OUT/base.log" 2>&1; "$B" docker-start >> "$OUT/base.log" 2>&1; minikube -p bek stop >> "$OUT/base.log" 2>&1; }
trap restore EXIT
if "$B" dump "$OUT/casdoor.sql" >> "$OUT/base.log" 2>&1 && "$B" docker-stop >> "$OUT/base.log" 2>&1 \
   && "$B" up "$OUT/casdoor.sql" >> "$OUT/base.log" 2>&1; then
  log "base in cluster up"
  # its digest against the reference cell of this batch
  REF=$OUT/b7/K9-X/digest.json KEEP_CLUSTER=1 "$X/runner9.sh" "$OUT/b7" K9-X-cb; log "inside done exit=$?"
else
  log "FAILED base in cluster (base.log)"
fi
restore; trap - EXIT
log ALL-DONE
