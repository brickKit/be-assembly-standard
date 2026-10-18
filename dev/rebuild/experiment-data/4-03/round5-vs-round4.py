"""Round 5 (performance power profile) against round 4 (profile not recorded), item by item, for the cells both have.

Prints, per metric and load, the median ratio round5/round4 and the spread of the ratios (10th and 90th percentile);
the request p50 ratio per operation; and the base cells' memory and idle CPU (the probe or shell container only,
not the base resources). Run: python3 round5-vs-round4.py <round4/measure> <round5/measure>
"""

import json
import statistics
import sys
from pathlib import Path


def results(root: Path) -> dict:
    out = {}
    for f in root.glob("run1/*/*/*/*/result.json"):
        d = json.loads(f.read_text())
        out[(d["cell"], d["caller"], d["callee"], d["op"], d["load"])] = d
    return out


def caller_cpu(d: dict) -> float | None:
    """CPU seconds per 1000 operations of the caller's container (process view)."""
    name = d["caller"].replace("/", "-")
    for c, v in d["resources"]["containers"].items():
        if name in c:
            return v["process"].get("cpu_seconds_per_1000")
    return None


METRICS = {
    "hop p50": lambda d: d["driver"]["hop_ms"]["P50"],
    "hop p99": lambda d: d["driver"]["hop_ms"]["P99"],
    "request p50": lambda d: d["driver"]["latency_ms"]["P50"],
    "request p99": lambda d: d["driver"]["latency_ms"]["P99"],
    "arrival p50": lambda d: d["completion"]["received"]["p50_ms"],
    "arrival p99": lambda d: d["completion"]["received"]["p99_ms"],
    "caller CPU / 1000": caller_cpu,
}


def pct(xs: list, q: float) -> float:
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def by_op(r4: dict, r5: dict, keys: list) -> None:
    """The request p50 ratio per operation and load: is the profile's effect the same everywhere?"""
    groups: dict = {}
    for k in keys:
        a, b = r4[k]["driver"]["latency_ms"]["P50"], r5[k]["driver"]["latency_ms"]["P50"]
        if a and b and not (r4[k]["driver"]["error_rate"] or r5[k]["driver"]["error_rate"]):
            groups.setdefault((k[3], k[4]), []).append(b / a)
    print("\nrequest p50 ratio per operation")
    for (op, load), rs in sorted(groups.items()):
        print(f"  {op:16} {load:>4}/s  n={len(rs):2}  median {statistics.median(rs):.2f}"
              f"  min {min(rs):.2f}  max {max(rs):.2f}")


def compare(r4: dict, r5: dict) -> None:
    keys = sorted(set(r4) & set(r5))
    print(f"items in both: {len(keys)}")
    for load in ("50", "200"):
        print(f"\nload {load}/s")
        for name, get in METRICS.items():
            ratios = []
            for k in keys:
                if k[4] != load or r4[k]["driver"]["error_rate"] or r5[k]["driver"]["error_rate"]:
                    continue
                try:
                    a, b = get(r4[k]), get(r5[k])
                except (KeyError, TypeError):
                    continue
                if a and b:
                    ratios.append(b / a)
            if ratios:
                print(f"  {name:18} n={len(ratios):3}  median {statistics.median(ratios):.2f}"
                      f"  p10 {pct(ratios, 0.1):.2f}  p90 {pct(ratios, 0.9):.2f}")


def base(root: Path) -> dict:
    out = {}
    for f in root.glob("run1/D-base-*/idle.json"):
        d = json.loads(f.read_text())
        own = [v["process"] for c, v in d["resources"]["containers"].items() if not c.startswith("be-")]
        mem = sum(v["memory_median"] for v in own)
        cores = sum(v["cores"] for v in own)
        out[d["cell"]] = (mem / 2**20, cores)
    return out


def main() -> None:
    r4root, r5root = Path(sys.argv[1]), Path(sys.argv[2])
    r4, r5 = results(r4root), results(r5root)
    compare(r4, r5)
    by_op(r4, r5, sorted(set(r4) & set(r5)))
    b4, b5 = base(r4root), base(r5root)
    print("\nbase cells: memory MiB and idle cores, round 4 -> round 5")
    for cell in sorted(set(b4) & set(b5)):
        print(f"  {cell:18} {b4[cell][0]:6.1f} -> {b5[cell][0]:6.1f}   {b4[cell][1]:.4f} -> {b5[cell][1]:.4f}")


if __name__ == "__main__":
    main()
