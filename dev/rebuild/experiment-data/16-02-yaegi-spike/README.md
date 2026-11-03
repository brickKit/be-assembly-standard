# Yaegi spike: gRPC over mTLS, and state across reloads (2026-11-03)

Foundations item 2, T2. The maintainer chose a Traefik Yaegi plugin for the edge session layer on condition that two
things hold; this spike checks both on Traefik v3.0.4 (the project's pinned image). `scripts/run.sh` does it all and
exits non-zero on any failure; its output is `out/run.txt` (exit 0).

1. **A gRPC unary call over mTLS from the plugin**, standard library only (grpc-go needs `unsafe`, which Yaegi
   plugins do not get): `scripts/plugin/` frames `grpc.health.v1.Health/Check` by hand (5-byte prefix, the protobuf
   field written by hand) and posts it with `net/http` over HTTP/2 with a client certificate; `scripts/server/` is
   grpc-go v1.83.2 (the version `be-sdk-go` uses) requiring and verifying a client certificate. Result: HTTP/2.0,
   `grpc-status` 0 and SERVING for a registered service; `grpc-status` 5 read from a trailers-only answer for an
   unknown one; the server logged the verified client certificate for both calls. Reverse check: the same call
   without a client certificate is refused at the handshake (curl exit 56).
2. **The package's state across a dynamic configuration reload** (Docker's provider reloads whenever a container
   starts or stops): adding a router to the watched file made Traefik call the plugin's `New` again (a new instance
   ID, `New` counted 2); the package-level ID stayed the same and the hit counter went on. So a cache held in a
   package variable survives reloads; one held in the middleware instance would not.

Not checked here: a Traefik restart (the cache is lost, as designed: each session exchanges once), several Traefik
replicas (each keeps its own cache and pulls the invalidations itself), Yaegi's interpretation of the real core
(the core's tests must also run under `yaegi test`).
