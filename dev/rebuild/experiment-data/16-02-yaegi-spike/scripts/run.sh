#!/usr/bin/env bash
# The Yaegi spike (foundations item 2, T2): a hand-framed gRPC unary call over mTLS from a Traefik v3.0.4 Yaegi
# plugin, and the plugin's package state across a dynamic configuration reload. Throwaway certificates are made in a
# temporary directory and deleted afterwards. Usage: run.sh (prints the evidence; exits non-zero on any failure)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d)
cleanup() { docker rm -f yaegi-spike >/dev/null 2>&1 || true; kill "$spid" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
(cd "$here/server" && go build -o "$tmp/server" .)
mkdir -p "$tmp/certs" "$tmp/traefik" && cd "$tmp/certs"
openssl req -x509 -newkey ed25519 -nodes -keyout ca.key -out ca.pem -days 1 -subj /CN=spike-ca 2>/dev/null
for n in server client; do
  openssl req -newkey ed25519 -nodes -keyout $n.key -out $n.csr -subj /CN=spike-$n 2>/dev/null
  printf 'subjectAltName=DNS:spike.component.test,URI:spiffe://test/component/infra/edge\n' > $n.ext
  openssl x509 -req -in $n.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out $n.pem -days 1 -extfile $n.ext 2>/dev/null
done
chmod 644 *.key
cp "$here/traefik/traefik.yml" "$tmp/traefik/"
dyn() { sed "s#__EXTRA__#$1#" "$here/traefik/dynamic.tmpl.yml" > "$tmp/traefik/dynamic.yml"; }
dyn ""
"$tmp/server" server.pem server.key ca.pem 127.0.0.1:18200 > "$tmp/server.log" 2>&1 & spid=$!
docker run -d --name yaegi-spike --network host -v "$tmp/traefik:/etc/traefik:ro" -v "$here/plugin:/plugins-local:ro" \
  -v "$tmp/certs:/certs:ro" traefik:v3.0.4@sha256:a208c74fd80a566d4ea376053bff73d31616d7af3f1465a7747b8b89ee34d97e >/dev/null
for i in $(seq 1 50); do curl -sf -o /dev/null localhost:18280/spike/state && break; sleep 0.2; done
echo "== 1. gRPC unary over mTLS from the Yaegi plugin"
a=$(curl -s 'localhost:18280/spike/grpc?service=be.spike'); echo "be.spike: $a"
echo "$a" | grep -q 'proto=HTTP/2.0 grpc-status=0 serving-status=1'
b=$(curl -s 'localhost:18280/spike/grpc?service=unknown'); echo "unknown: $b"
echo "$b" | grep -q 'grpc-status=5'
echo "-- the server saw a verified client certificate:"; grep 'verified client spike-client' "$tmp/server.log"
echo "-- reverse check: the same call without a client certificate is refused by the server:"
if curl -s --http2 --cacert ca.pem --resolve spike.component.test:18200:127.0.0.1 -o /dev/null -w '%{http_code}\n' \
  -H 'Content-Type: application/grpc' --data-binary @/dev/null https://spike.component.test:18200/grpc.health.v1.Health/Check; then
  echo "FAIL: accepted without a client certificate"; exit 1
else echo "refused (curl exit $?)"; fi
echo "== 2. package state across a dynamic configuration reload"
before=$(curl -s -D - -o /dev/null localhost:18280/spike/state | grep -i '^x-' | tr -d '\r' | sort); echo "$before"
dyn '    other:\n      rule: PathPrefix(`/other`)\n      entryPoints: [web]\n      service: none'
for i in $(seq 1 50); do
  after=$(curl -s -D - -o /dev/null localhost:18280/spike/state | grep -i '^x-' | tr -d '\r' | sort)
  [ "$(echo "$after" | grep -i x-news)" != "$(echo "$before" | grep -i x-news)" ] && break; sleep 0.2
done
echo "-- after the reload:"; echo "$after"
test "$(echo "$after" | grep -i x-news)" != "$(echo "$before" | grep -i x-news)"   # precondition: New ran again
test "$(echo "$after" | grep -i x-instance)" != "$(echo "$before" | grep -i x-instance)"
test "$(echo "$after" | grep -i x-package)" = "$(echo "$before" | grep -i x-package)" # the package state stayed
echo "== both hold"
