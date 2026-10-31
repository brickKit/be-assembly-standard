#!/usr/bin/env python3
"""Per crash in faults.jsonl: the seconds of the load's series (from the crash to 30 s after) whose p95 was over 1 s,
and how many requests that window sent and failed (list.order 404s apart). Usage: slow.py <cell dir>"""
import json, pathlib, sys
d = pathlib.Path(sys.argv[1])
series = json.load(open(d / "series.json"))
for r in map(json.loads, open(d / "faults.jsonl")):
    rows = [x for x in series if r["kill_at"] - 1 <= x["unix"] <= r["kill_at"] + 30]
    slow = [x for x in rows if (x.get("p95_ms") or 0) > 1000]
    failed = sum(n for x in rows for k, n in (x.get("errors") or {}).items() if not k.startswith("list.order: 404"))
    print(f"up {r['up_after']:>4} s; seconds with p95 > 1 s: {len(slow):>2}; failed {failed:>2}; "
          f"max p95 {max(x.get('p95_ms') or 0 for x in rows):>7.0f} ms")
