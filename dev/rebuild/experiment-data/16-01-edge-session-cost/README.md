# The per-request cost of an edge session layer (2026-11-03)

Foundations item 2, T2: what each request pays for the edge's session layer (protocol 20, D61) in the three forms
left after reading the docs (http-wasm has no outbound network and passes to the next handler once, so it cannot
exchange a token or replay; forward auth cannot replay either). Every form does the same work on a cache hit: read
the `be_session` cookie, SHA-256 it, look the token up in a `sync.Map`, set `Authorization`. Nothing else (no
exchange, no replay): this is the floor of the steady state.

- Traefik v3.0.4 (the project's pinned image, Go 1.22.4; `runs/traefik-version.txt`), host network, file provider,
  log level ERROR, no access log. Backend and sidecar compiled with Go 1.27.2; the backend answers a 60-byte JSON and,
  on the session paths, 401 unless the injected token is exactly the cached one (the precondition that the layer
  did its work; `preconditions.txt`: every path 200 with the cookie, the session paths 401 without it).
- Paths: **a** direct; **b** the Yaegi middleware (`scripts/plugin/`); **c** the compiled sidecar behind Traefik,
  forwarding to Traefik's inner entrypoint (hairpin); **d** the same sidecar in front of Traefik (one extra hop, no
  TLS in either; a sidecar in front would have to terminate TLS instead of Traefik).
- Load: `scripts/load/` open loop, 2 000 requests/s for 20 s per run, latency from each request's scheduled instant;
  CPU = utime+stime of the Traefik process plus the sidecar from `/proc/<pid>/stat` across the run, divided by the
  requests. Performance power mode, set and restored by `scripts/run.sh` (`power.txt`). Two sets, 6 rounds each,
  the order rotated each round: `runs/` (a b c), `runs-d/` (a b d). Load average 0.9–1.9 before and after
  (`uptime-*.txt`); compare within one set only.

| set | path | edge CPU µs/request, median (min–max) | over a | p50 ms | p99 ms, median (min–max) |
| --- | --- | --- | --- | --- | --- |
| runs | a | 141.0 (139.0–157.2) | — | 0.61 | 1.35 (1.32–1.49) |
| runs | b | 175.6 (160.2–181.2) | +35 | 0.66 | 1.43 (1.37–1.51) |
| runs | c | 496.9 (460.2–560.0): Traefik 292.0, sidecar 204.9 | +356 | 0.71 | 1.73 (1.68–2.23) |
| runs-d | a | 127.6 (127.0–128.2) | — | 0.59 | 1.30 (1.28–1.31) |
| runs-d | b | 150.0 (148.2–151.0) | +22 | 0.60 | 1.30 (1.29–1.32) |
| runs-d | d | 294.0 (290.8–296.0): Traefik 138.9, sidecar 155.1 | +166 | 0.73 | 1.45 (1.44–1.46) |

Every run answered all 40 000 requests with 200 (`runs*/runs.jsonl`, the `load.ok` field). The variation within a
set: a's CPU spans 13% in `runs` and 1% in `runs-d`; every difference above is far outside it. Between the sets a
moved 141 → 128 (drift, not compared).

Reading: the Yaegi middleware adds about 22–35 µs of edge CPU a request and no visible latency; a compiled sidecar
adds 166 µs in front of Traefik and 356 µs behind it (Traefik runs twice), and 0.1–0.4 ms at p99. For scale, the
trivial backend used 59–78 µs a request (the `backend` ticks; the kb record's `summarize.py` prints them). Recompute with `python3` over `runs*/runs.jsonl` (the summary in the
plan's T2). Rerun: `scripts/run.sh <out> 6 2000 20 "a b c"` after building `scripts/{backend,proxy,load}` into
`scripts/bin-*`.
