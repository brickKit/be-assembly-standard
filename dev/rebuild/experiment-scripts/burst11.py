#!/usr/bin/env python3
"""Step 11 R3: per cell, the burst of billing and printing (burst/burst.json) and the background mix's per-second
p95 in the 5 minutes before it and during it (series.json). Usage: burst11.py <cell dir>..."""
import json
import pathlib
import statistics
import sys

for arg in sys.argv[1:]:
    d = pathlib.Path(arg)
    b = json.load(open(d / "burst" / "burst.json"))
    s = json.load(open(d / "burst" / "burst-series.json"))
    a, z = s[0]["unix"], s[-1]["unix"]
    bg = json.load(open(d / "series.json"))
    during = [x["p95_ms"] for x in bg if a <= x["unix"] <= z and x.get("p95_ms")]
    before = [x["p95_ms"] for x in bg if a - 300 <= x["unix"] < a and x.get("p95_ms")]
    print(f"{d.name}: burst {b['sent']} sent, {b['ok']} ok, p50 {b['latency_ms']['P50']:.1f} ms, p95 {b['latency_ms']['P95']:.1f} ms"
          f" | mix p95 per second, median: before {statistics.median(before):.1f} ms, during {statistics.median(during):.1f} ms;"
          f" max during {max(during):.1f} ms")
