#!/bin/bash
# (Re)creates the K row's minikube profile bek: docker driver, Kubernetes v1.35.1, bridge CNI, no CPU or memory limit.
# The host ports are fixed when the node is created: 18082-18605 to node ports 30082-30605, the components' NodePorts
# (cells/units.py nodeports, step 9); and, since step 10 B7, 15432, 14222, 19000, 18000 to node ports 31432, 31422,
# 31900, 31800, the base resources when they run in the cluster (base-cluster.sh). Distinct host ports, because the
# node binds all of them whenever it starts, and Docker's base resources hold 5432, 4222, 9000 and 8000.
# Deletes an existing bek first (nothing in it is kept: every cell deploys again and loads its images).
# Usage: cluster-create.sh   (leaves the node stopped, as the runners expect)
set -eu
COMPONENT_PORTS="18082:30082 18083:30083 18084:30084 18086:30086 18088:30088 18089:30089 18090:30090 18200:30200
18206:30206 18223:30223 18224:30224 18225:30225 18226:30226 18400:30400 18402:30402 18600:30600 18601:30601
18602:30602 18603:30603 18604:30604 18605:30605"
BASE_PORTS="15432:31432 14222:31422 19000:31900 18000:31800"
args=()
for p in $COMPONENT_PORTS $BASE_PORTS; do args+=(--ports="$p"); done
minikube -p bek delete || true
minikube -p bek start --driver=docker --kubernetes-version=v1.35.1 --container-runtime=docker --cni=bridge \
  --cpus=no-limit --memory=no-limit "${args[@]}"
minikube -p bek stop
