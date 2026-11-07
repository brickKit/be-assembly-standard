#!/usr/bin/env python3
"""Summary of run.sh's raw.txt: per batch and function the median, min and max of the inserts (ms), the pinned
function's extra cost per row (median pinned - median plain, over 50,000 rows), and the spread between the batches."""
import statistics
import sys
from collections import defaultdict

rows = defaultdict(list)
for line in open(sys.argv[1]):
    batch, _, fn, ms = line.split()
    rows[(batch, fn)].append(float(ms))
med = {}
for (batch, fn), v in sorted(rows.items()):
    med[(batch, fn)] = statistics.median(v)
    print(f"batch {batch} {fn:8s} n={len(v):2d} median={med[(batch, fn)]:8.1f} min={min(v):8.1f} max={max(v):8.1f} ms")
for batch in sorted({b for b, _ in rows}):
    plain, pinned, none = med[(batch, "f_plain")], med[(batch, "f_pinned")], med[(batch, "none")]
    print(f"batch {batch}: pinned - plain = {pinned - plain:.1f} ms / 50000 rows = {(pinned - plain) / 50:.3f} us/row "
          f"({(pinned - plain) / plain * 100:.1f}% of the insert with the plain trigger); "
          f"trigger itself (plain - none) = {(plain - none) / 50:.3f} us/row")
for fn in ("f_plain", "f_pinned", "none"):
    a, b = med[("1", fn)], med[("2", fn)]
    print(f"spread {fn}: batch 1 vs 2 medians differ by {abs(a - b) / min(a, b) * 100:.1f}%")
