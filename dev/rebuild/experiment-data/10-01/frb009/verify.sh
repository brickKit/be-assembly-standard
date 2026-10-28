#!/bin/bash
# FRB-009 retest: one Python probe image with no ENV PORT serves both test/probe-py (8601) and test/probe-py2 (8605),
# on Docker and on rootless Podman, through brickkit up. Original tags restored whatever happens.
# Usage: verify.sh (builds pyvar-noport:1 from Dockerfile.noport) | IMG=pyvar-pbs:1 DOCKER_ONLY=1 verify.sh
# check.py <cell copy>...: PORT per service against the health check or containerPort, after up --dry-run in each copy
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }  # as cell-chain.sh: secrets read at run time
export BE_ACC_NATS_URL=nats://localhost:4222 BE_ACC_S3_URL=http://localhost:9000
export BE_ACC_S3_ACCESS_KEY BE_ACC_S3_SECRET_KEY; BE_ACC_S3_ACCESS_KEY=$(envval STORAGE_ACCESS_KEY); BE_ACC_S3_SECRET_KEY=$(envval STORAGE_SECRET_KEY)
S=$(cd "$(dirname "$0")" && pwd); C=${TMPDIR:-/tmp}/frb009-pyonly
SRC=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/probes/py
rm -rf "$C"; cp -a /home/zhijie/Desktop/github/be-assembly-standard/dev/rebuild/experiment-cells/D9-probe-pyonly "$C"
IMG=${IMG:-pyvar-noport:1}; [ "$IMG" = pyvar-noport:1 ] && { docker build -q -f "$S/Dockerfile.noport" -t pyvar-noport:1 "$SRC" >/dev/null || exit 1; }
echo "image PORT: $(docker run --rm --entrypoint sh "$IMG" -c 'echo ${PORT-unset}')"
restore() {
  for p in test-probe-py test-probe-py2; do
    docker tag "$p:3.2.19-orig" "$p:3.2.19"
    podman rmi -f "localhost/$p:3.2.19" "docker.io/library/$p:3.2.19" >/dev/null 2>&1
  done
  echo restored
}
trap restore EXIT
for p in test-probe-py test-probe-py2; do docker tag "$IMG" "$p:3.2.19"; done
health() { # engine
  sleep 20
  $1 ps -a --format '{{.Names}} {{.Status}}' | grep -E 'probe-py' 
  for n in $($1 ps -a --format '{{.Names}}' | grep -E 'probe-py' | grep -v migration); do
    echo "$n env PORT=$($1 exec "$n" sh -c 'echo $PORT')"; done
}
cd "$C"
echo "== docker"; unset CONTAINER_HOST
brickkit up > "$S/up-docker.log" 2>&1; echo "up exit=$?"; health docker
brickkit down > "$S/down-docker.log" 2>&1; echo "down exit=$?"
echo "== podman (rootless)"
[ -n "${DOCKER_ONLY:-}" ] && exit 0
for p in test-probe-py test-probe-py2; do docker save "$p:3.2.19" | podman load -q >/dev/null && podman tag "docker.io/library/$p:3.2.19" "localhost/$p:3.2.19"; done
sed -i 's/^target: docker$/target: podman/' deploy.yaml
brickkit up > "$S/up-podman.log" 2>&1; echo "up exit=$?"; health podman
brickkit down > "$S/down-podman.log" 2>&1; echo "down exit=$?"
grep -cE '^\s*- PORT=' .brickkit/generated/compose.yaml
