#!/usr/bin/env python3
"""Step 8: the same cell in two perf passes (R8.2, R8.3) side by side, with the key numbers the plan's R8.4 rule
looks at (step8-plan.md: whole-deployment memory, CPU seconds per 1000 requests, confirm p95; a difference beyond
10% sends the cell to R8.4). cgroup readings as in r8-summary.py.
Usage: r8-compare.py <pass-1 dir> <pass-2 dir> <cell>... (each <dir>/<cell> holding idle.json and mix.json, or run/)"""
import json
import pathlib
import sys

BASE = ("be-postgres", "be-nats", "be-rustfs", "be-seaweedfs", "be-casdoor")
MIB = 1024 * 1024


def load(d: pathlib.Path, name: str) -> dict:
    return json.loads(((d / "run") if (d / "run").is_dir() else d).joinpath(name).read_text())


def keys(d: pathlib.Path) -> dict:
    mix, idle = load(d, "mix.json"), load(d, "idle.json")
    r, n = mix["resources"], mix["resources"]["requests"]
    comp = sum(c["cgroup"]["cores"] for k, c in r["containers"].items() if k not in BASE)
    mem = sum(c["cgroup"]["memory_median"] for c in r["containers"].values()) + r["platform"]["memory_median"]
    comp_mem = sum(c["cgroup"]["memory_median"] for k, c in r["containers"].items() if k not in BASE)
    idle_comp = sum(c["cgroup"]["cores"] for k, c in idle["resources"]["containers"].items() if k not in BASE)
    ops = mix["driver"]["mix"]["ops"]
    return {
        "whole memory MiB": mem / MIB,
        "component memory MiB": comp_mem / MIB,
        "component RSS MiB": sum(c["process"]["memory_median"] for k, c in r["containers"].items() if k not in BASE) / MIB,
        "component CPU s / 1000 req": comp * r["elapsed"] / n * 1000,
        "platform CPU s / 1000 req": r["platform"]["cores"] * r["elapsed"] / n * 1000,
        "idle component cores": idle_comp,
        "p95 ms": mix["driver"]["latency_ms"]["P95"],
        "confirm p95 ms": ops["confirm"]["latency_ms"]["P95"],
        "bill p95 ms": ops["bill"]["latency_ms"]["P95"],
        "issue to completed p95 ms": mix["completion"]["issue_to_completed_ms"]["P95"],
    }


def main(a: str, b: str, cells: list[str]) -> None:
    print("| cell | number | pass 1 | pass 2 | difference |")
    print("| --- | --- | --- | --- | --- |")
    for c in cells:
        x, y = keys(pathlib.Path(a) / c), keys(pathlib.Path(b) / c)
        for k in x:
            diff = (y[k] - x[k]) / x[k] * 100 if x[k] else 0.0
            flag = " **>10%**" if abs(diff) > 10 else ""
            print(f"| {c} | {k} | {x[k]:.3f} | {y[k]:.3f} | {diff:+.1f}%{flag} |")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
