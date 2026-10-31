#!/bin/bash
# Step 11 follow-up (11-01, section 8): sets the probes of one component's Deployment in a K cell, then waits for the
# rollout (a new Pod, so kubelet's restart back-off starts over). v1.10.2 (also "default", its name in the first run)
# = what BrickKit 1.10.2 writes (startup probe every 5 s; readiness after 5 s, every 5 s); v1.10.3 = what 1.10.3 writes
# (startup every 1 s; readiness from the start, every 5 s); fast = startup every 1 s, readiness from the start, every
# 1 s. The startup budget stays 60 s; liveness and the failure thresholds stay as written. Prints the probes the new
# Pod runs. events (no change) prints the probe events and starts of the component's Pods so far.
# Usage: probes11.sh <cell> <component> v1.10.2|v1.10.3|fast|events
#   (runner11.sh: FAULTS entry "sh:probes11.sh K9-S erp/sales fast")
set -euo pipefail
CELL=$1; COMP=$2; MODE=$3
R=/home/zhijie/Desktop/github/be-assembly-standard; D=$R/dev/rebuild/experiment-cells/$CELL
NS=$(sed -n 's/^ *namespace: *//p' "$D/deploy.yaml")
VER=$(grep -oE "${COMP}@[0-9.]+" "$D/cell.yaml" | head -1 | cut -d@ -f2)
NAME=${COMP//\//-}; DEPLOY=$NAME-${VER//./-}
K() { minikube -p bek kubectl -- -n "$NS" "$@"; }
case $MODE in
  events)
    K get events --sort-by=.lastTimestamp -o json | python3 -c '
import json, sys
for e in json.load(sys.stdin)["items"]:
    o = e["involvedObject"]
    if o.get("kind") == "Pod" and o.get("name", "").startswith(sys.argv[1] + "-") and e["reason"] in ("Unhealthy", "Started", "Killing", "BackOff"):
        print(e.get("firstTimestamp") or e.get("eventTime"), e.get("lastTimestamp"), e.get("count"), o["name"], e["reason"], e.get("message", "")[:120])' "$DEPLOY"
    exit 0 ;;
  v1.10.3) S='{"periodSeconds":1,"failureThreshold":60}'; RD='{"initialDelaySeconds":0,"periodSeconds":5}' ;;
  default|v1.10.2) S='{"periodSeconds":5,"failureThreshold":12}'; RD='{"initialDelaySeconds":5,"periodSeconds":5}' ;;
  fast) S='{"periodSeconds":1,"failureThreshold":60}'; RD='{"initialDelaySeconds":0,"periodSeconds":1}' ;;
  *) echo "unknown mode $MODE" >&2; exit 2 ;;
esac
K patch deploy "$DEPLOY" --type=strategic \
  -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$NAME\",\"startupProbe\":$S,\"readinessProbe\":$RD}]}}}}"
K rollout status deploy "$DEPLOY" --timeout=180s
sleep 20  # the old Pod gone, the NodePort's endpoints settled
K get pods -l "app=$DEPLOY" -o json 2>/dev/null | python3 -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    c = p["spec"]["containers"][0]
    print(p["metadata"]["name"], p["status"].get("phase"), "startup", json.dumps(c.get("startupProbe")),
          "readiness", json.dumps(c.get("readinessProbe")))'
K get deploy "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].startupProbe.periodSeconds} {.spec.template.spec.containers[0].readinessProbe.periodSeconds}{"\n"}'
# how the node routes a Service whose Pod is not ready (the requests that wait in 11-01's K rows go through it)
minikube -p bek kubectl -- -n kube-system get cm kube-proxy -o jsonpath='{.data.config\.conf}' | grep -E '^mode:' || true
