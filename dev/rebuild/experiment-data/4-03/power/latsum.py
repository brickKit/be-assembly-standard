"""Summarizes write results under a measure directory: per version, the request p50/p99, the writer's and
PostgreSQL's cores and the write-to-publish p50, over every round and both paths."""
import json, pathlib, statistics as st, sys
by = {}
for f in sorted(pathlib.Path(sys.argv[1]).glob("r*/*/**/write/50/result.json")):
    v = f.relative_to(sys.argv[1]).parts[1]
    o = json.loads(f.read_text()); c = o["resources"]["containers"]; caller = o["caller"].split("/")[1]
    w = [k for k in c if f"-{caller}-3" in k][0]
    by.setdefault(v, []).append((o["driver"]["latency_ms"]["P50"], o["driver"]["latency_ms"]["P99"], c[w]["process"]["cores"],
                                 c["be-postgres"]["process"]["cores"], o["completion"]["published"]["p50_ms"]))
for v, rows in sorted(by.items()):
    p50 = [r[0] for r in rows]
    print(f"{v}: n={len(rows)} request p50 median {st.median(p50):.2f} ms (range {min(p50):.2f}-{max(p50):.2f}), "
          f"p99 median {st.median([r[1] for r in rows]):.2f}, writer {st.median([r[2] for r in rows]):.2f} cores, "
          f"pg {st.median([r[3] for r in rows]):.2f} cores, publish p50 {st.median([r[4] for r in rows]):.1f} ms")
