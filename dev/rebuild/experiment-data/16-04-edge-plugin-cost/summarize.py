#!/usr/bin/env python3
"""The table of README.md from runs*/runs.jsonl: Traefik's CPU per request (utime+stime, 10 ms ticks), latencies."""
import json
import pathlib
import statistics as st

here = pathlib.Path(__file__).resolve().parent
for d in ["runs", "runs-noclone", "runs-nointerceptor"]:
    rows = [json.loads(line) for line in open(here / d / "runs.jsonl")]
    print(f"== {d}: {len(rows)} runs, every request 200: {all(r['load']['ok'] == r['load']['requests'] for r in rows)}")
    for p in "ab":
        rs = [r for r in rows if r["path"] == p]
        cpu = [r["traefik_ticks"] * 10000 / r["load"]["requests"] for r in rs]
        p50 = [r["load"]["p50_ms"] for r in rs]
        p99 = [r["load"]["p99_ms"] for r in rs]
        print(f"{p}: edge {st.median(cpu):.1f} us ({min(cpu):.1f}-{max(cpu):.1f}); p50 {st.median(p50):.2f} ms; "
              f"p99 {st.median(p99):.2f} ms ({min(p99):.2f}-{max(p99):.2f})")
