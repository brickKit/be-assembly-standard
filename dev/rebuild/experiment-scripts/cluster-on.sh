#!/bin/bash
# Starts the minikube node of the K row (profile bek) and returns once a pod can resolve host.minikube.internal the way
# the components do. Right after a start, CoreDNS reports ready while lookups from pods still fail for a minute or so:
# Go's resolver retries through it, musl's (the Alpine images: the Python probes) gives up at once with EAI_AGAIN, and
# a migration Job that fails is not run again, so the cell never comes up (step 9, K row probes). The check runs
# getent in an Alpine pod, which resolves through musl like those images.
# Usage: cluster-on.sh [log]
set -u
LOG=${1:-/dev/null}
R=/home/zhijie/Desktop/github/be-assembly-standard
export PATH=$R/dev/rebuild/experiment-scripts/bin:$PATH  # kubectl
KUBE=(kubectl --context bek)
minikube -p bek status >/dev/null 2>&1 || minikube -p bek start >> "$LOG" 2>&1 || { echo "minikube start failed"; exit 1; }
"${KUBE[@]}" -n kube-system rollout status deployment/coredns --timeout=180s >> "$LOG" 2>&1 || { echo "coredns not ready"; exit 1; }
minikube -p bek image load alpine:latest >> "$LOG" 2>&1
for i in $(seq 1 36); do
  if "${KUBE[@]}" -n default run "dns-wait-$i" --rm -i --restart=Never --image=alpine:latest --image-pull-policy=Never \
       --command -- getent hosts host.minikube.internal >> "$LOG" 2>&1; then
    echo "pod DNS ready after $i tries" >> "$LOG"; exit 0
  fi
  sleep 5
done
echo "pod DNS not ready after 3 min"; exit 1
