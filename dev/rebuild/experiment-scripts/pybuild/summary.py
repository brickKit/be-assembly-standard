#!/usr/bin/env python3
"""The tables of the Python build comparison from run.sh's output: per pass (<n>-<variant>/run1/D9-probe-pyonly),
the two probes' CPU seconds per 1000 requests (cgroup, caller + callee) and latency per operation, both directions
added; then per variant the mean of its two passes and the spread between them (the batch's fluctuation).
Usage: summary.py <run.sh out>"""
import json
import pathlib
import statistics
import sys

OUT = pathlib.Path(sys.argv[1])
OPS = ["echo-1k-grpc", "echo-1k-http", "write", "relay"]
DIRS = ["probe-py--probe-py2", "probe-py2--probe-py"]


def probes(res: dict) -> list[dict]:
    return [v["cgroup"] for k, v in res["containers"].items() if "test-probe-py" in k]


passes = []
for d in sorted(OUT.glob("*-*/run1/D9-probe-pyonly"), key=lambda p: int(p.parts[-3].split("-")[0])):
    n, variant = d.parts[-3].split("-", 1)
    idle = json.loads((d / "idle.json").read_text())["resources"]
    row = {"pass": int(n), "variant": variant,
           "idle_cores": sum(g["cores"] for g in probes(idle)),
           "idle_anon": sum(g["anon_median"] for g in probes(idle)) / 2**20}
    for op in OPS:
        cpu, p50, p99 = [], [], []
        for di in DIRS:
            r = json.loads((d / di / op / "200" / "result.json").read_text())
            assert r["driver"]["ok"] == r["driver"]["sent"], (d, di, op)
            cpu.append(sum(g["cpu_seconds_per_1000"] for g in probes(r["resources"])))
            p50.append(r["driver"]["latency_ms"]["P50"])
            p99.append(r["driver"]["latency_ms"]["P99"])
        row[op] = (statistics.mean(cpu), statistics.mean(p50), statistics.mean(p99))
    passes.append(row)

print("| pass | variant | idle cores | idle anon MiB | " + " | ".join(f"{o} CPU s/1000 · p50 · p99" for o in OPS) + " |")
print("| --- " * (4 + len(OPS)) + "|")
for r in passes:
    print(f"| {r['pass']} | {r['variant']} | {r['idle_cores']:.4f} | {r['idle_anon']:.1f} | "
          + " | ".join(f"{r[o][0]:.3f} · {r[o][1]:.2f} · {r[o][2]:.2f}" for o in OPS) + " |")

print()
print("| variant | " + " | ".join(f"{o} CPU s/1000 (spread)" for o in OPS) + " | mean CPU vs slim | idle anon MiB |")
print("| --- " * (len(OPS) + 3) + "|")
base = None
for v in ["slim", "alpine", "pbs"]:
    rs = [r for r in passes if r["variant"] == v]
    cells, means = [], []
    for o in OPS:
        xs = [r[o][0] for r in rs]
        m = statistics.mean(xs)
        means.append(m)
        cells.append(f"{m:.3f} (±{(max(xs) - min(xs)) / 2 / m * 100:.1f}%)")
    total = statistics.mean(means)
    base = base or total
    print(f"| {v} | " + " | ".join(cells) + f" | {(total / base - 1) * 100:+.1f}% | "
          f"{statistics.mean(r['idle_anon'] for r in rs):.1f} |")
