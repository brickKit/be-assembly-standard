#!/usr/bin/env bash
# The per-request cost of the real be-edge plugin (cache hit) on Traefik v3.0.4: a = direct, b = the plugin.
# Paired, rotating rounds in performance power mode (restored at the end, also when stopped). Throwaway certificates
# in a temporary directory. Usage: run.sh <out dir> [rounds] [rate] [seconds]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); out=$(realpath -m "$1"); rounds=${2:-6}; rate=${3:-2000}; secs=${4:-20}
edge=/home/zhijie/Desktop/github/be-assembly-standard/tools/be-edge
mkdir -p "$out"; tmp=$(mktemp -d)
prev=$(powerprofilesctl get)
cleanup() { docker rm -f edgecost2-traefik >/dev/null 2>&1 || true; kill $(jobs -p) 2>/dev/null || true; rm -rf "$tmp"; powerprofilesctl set "$prev"; }
trap cleanup EXIT
dep=0190f3a1-0000-7000-8000-00000000d001
cd "$tmp"
openssl req -x509 -newkey ed25519 -nodes -keyout ca.key -out ca.pem -days 1 -subj /CN=ca 2>/dev/null
mk() { openssl req -newkey ed25519 -nodes -keyout $1.key -out $1.csr -subj /CN=$1 2>/dev/null
  printf "subjectAltName=$2\nextendedKeyUsage=serverAuth,clientAuth\n" > $1.ext
  openssl x509 -req -in $1.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out $1.pem -days 1 -extfile $1.ext 2>/dev/null; }
mk iam "DNS:infra.iam-casdoor.component.$dep,URI:spiffe://$dep/component/infra/iam-casdoor"
mk edge "DNS:infra.edge.component.$dep,URI:spiffe://$dep/component/infra/edge"
chmod 644 *.key
mkdir traefik
cat > traefik/traefik.yml <<EOT
entryPoints:
  web:
    address: "127.0.0.1:18080"
providers:
  file:
    filename: /etc/traefik/dynamic.yml
log:
  level: ERROR
experimental:
  localPlugins:
    beedge:
      moduleName: github.com/brickKit/be-edge/v3
EOT
cat > traefik/dynamic.yml <<EOT
http:
  routers:
    a:
      rule: PathPrefix(\`/a\`)
      entryPoints: [web]
      service: backend
    b:
      rule: PathPrefix(\`/b\`)
      entryPoints: [web]
      middlewares: [edge]
      service: backend
  middlewares:
    edge:
      plugin:
        beedge:
          identityAddress: "127.0.0.1:18201"
          identityComponent: infra/iam-casdoor
          deployment: "$dep"
          certFile: $tmp/edge.pem
          keyFile: $tmp/edge.key
          caFile: $tmp/ca.pem
  services:
    backend:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:18100
EOT
powerprofilesctl set performance
echo "power: $(powerprofilesctl get) (was $prev)" | tee "$out/power.txt"
echo "be-edge $(git -C $edge rev-parse --short HEAD) $(git -C $edge status --short | wc -l) uncommitted" | tee "$out/edge-version.txt"
uptime | tee "$out/uptime-before.txt"
"$here/bin-backend" "$here/token.txt" 127.0.0.1:18100 & bpid=$!
"$here/bin-fakeiam" "$here/token.txt" iam.pem iam.key 127.0.0.1:18201 & 
docker run -d --name edgecost2-traefik --network host -v "$tmp:$tmp:ro" -v "$tmp/traefik:/etc/traefik:ro" \
  -v "$edge:/plugins-local/src/github.com/brickKit/be-edge/v3:ro" \
  traefik:v3.0.4@sha256:a208c74fd80a566d4ea376053bff73d31616d7af3f1465a7747b8b89ee34d97e >/dev/null
for i in $(seq 1 100); do curl -sf -o /dev/null --cookie be_session=measurement-session-cookie http://127.0.0.1:18080/b && break; sleep 0.2; done
tpid=$(docker inspect -f '{{.State.Pid}}' edgecost2-traefik)
# preconditions: the plugin injects the identity member's token (the backend checks it), and refuses without a cookie
test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/a)" = 200
test "$(curl -s -o /dev/null -w '%{http_code}' --cookie be_session=measurement-session-cookie http://127.0.0.1:18080/b)" = 200
test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/b)" = 401
echo "preconditions ok" | tee "$out/preconditions.txt"
cpu() { awk '{print $14+$15}' /proc/$1/stat; }
for p in a b; do "$here/bin-load" -url http://127.0.0.1:18080/$p -rate "$rate" -d 3s -label warm-$p >> "$out/warmup.jsonl"; done
for r in $(seq 1 "$rounds"); do
  if [ $((r % 2)) = 1 ]; then order="a b"; else order="b a"; fi
  for p in $order; do
    t0=$(cpu "$tpid"); k0=$(cpu "$bpid")
    line=$("$here/bin-load" -url http://127.0.0.1:18080/$p -rate "$rate" -d "${secs}s" -label "$p")
    t1=$(cpu "$tpid"); k1=$(cpu "$bpid")
    echo "{\"round\":$r,\"path\":\"$p\",\"tick\":$(getconf CLK_TCK),\"traefik_ticks\":$((t1-t0)),\"proxy_ticks\":0,\"backend_ticks\":$((k1-k0)),\"load\":$line}" | tee -a "$out/runs.jsonl"
  done
done
docker logs edgecost2-traefik > "$out/traefik.log" 2>&1 || true
uptime | tee "$out/uptime-after.txt"
