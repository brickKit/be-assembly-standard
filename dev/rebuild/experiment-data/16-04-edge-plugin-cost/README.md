# The real be-edge plugin's per-request cost (2026-11-03)

Foundations item 2, T4: the per-request cost of be-edge (commit `b062bbd`, what became v3.0.0-alpha.1 with only log
and doc changes) on Traefik v3.0.4, on a cache hit, against the floor measured in 16-01 (a Yaegi middleware that
only reads the cookie, hashes it, looks the token up and injects it: +22-35 us).

- `scripts/run.sh`: Traefik v3.0.4 (host network, file provider, log level ERROR), the plugin mounted from the
  repository, `scripts/fakeiam` (a grpc-go SessionService over TLS answering one token, so the first exchange
  succeeds), the 16-01 backend (which answers 401 unless the injected token is exactly that one) and load generator.
  a = direct, b = the plugin; 2 000 requests/s for 20 s per run, the order alternating each round; performance power
  mode set and restored (`power.txt`). Preconditions in `preconditions.txt`.
- `runs/`: the plugin as committed, 6 rounds. `runs-noclone/`: a variant that prepared the request in place instead
  of `r.Clone` (3 rounds; not kept: no gain). `runs-nointerceptor/`: a probe that passed the response writer straight
  through, without the interceptor that holds a 401 back (3 rounds; a measurement only, never committed: the edge must
  see a 401 before it decides to replay). Each set compared within itself only (`a` moved 138 -> 150 between sets).
- `summarize.py` prints the table (`summary.txt`).

| set | a: edge CPU us/request (min-max) | b: edge CPU us/request (min-max) | b over a | p50 a / b | p99 a / b |
| --- | --- | --- | --- | --- | --- |
| runs | 138.0 (133.5-142.8) | 228.4 (226.5-240.0) | +90 | 0.60 / 0.70 ms | 1.31 / 1.45 ms |
| runs-noclone | 149.8 (147.0-150.0) | 248.0 (245.2-248.8) | +98 | 0.63 / 0.74 ms | 1.36 / 1.53 ms |
| runs-nointerceptor | 150.5 (149.8-154.5) | 212.5 (212.2-214.2) | +62 | 0.63 / 0.69 ms | 1.35 / 1.47 ms |

Every run answered all its requests with 200. Within a set, a varies by 3-7%.

Reading: the real plugin adds about 90 us of edge CPU a request on a cache hit, about three times the floor of
16-01, and 0.1 ms at p50 and p99. Of that, about 36 us is the interceptor (the reverse proxy, native code, calling the
interpreted writer's Header, WriteHeader and Write); copying the request (`r.Clone`) costs nothing measurable; the
rest is the plugin's own steps run by the interpreter. It stays under the compiled sidecar's floor of 16-01 (+166 us
in front of Traefik, +356 us behind it, for a proxy that did nothing but inject). The task's own bar ("no more than
the 16-01 plugin reading plus noise") is not met; recorded as is, in the plan's T4.
