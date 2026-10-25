#!/usr/bin/env python3
"""Step 8 R8.2e: each cell idle without seed or baseline data next to the same cell idle with them (R8.2), cgroup
readings as in r8-summary.py. Usage: r8-empty-summary.py <empty round dir> <R8.2 dir> <cell>..."""
import json
import pathlib
import sys

BASE = ("be-postgres", "be-nats", "be-rustfs", "be-seaweedfs", "be-casdoor")
MIB = 1024 * 1024


def idle(d: pathlib.Path) -> dict:
    f = d / "run" / "idle.json" if (d / "run").is_dir() else d / "idle.json"
    return json.loads(f.read_text())["resources"]


def parts(r: dict) -> dict:
    out = {"components": [0.0, 0.0], "base": [0.0, 0.0]}
    for name, c in r["containers"].items():
        k = "base" if name in BASE else "components"
        out[k][0] += c["cgroup"]["cores"]
        out[k][1] += c["cgroup"]["memory_median"]
    out["platform"] = [r["platform"]["cores"], r["platform"]["memory_median"]]
    return out


def main(empty: str, seeded: str, cells: list[str]) -> None:
    print("| cell | part | empty cores | empty MiB | with data cores | with data MiB |")
    print("| --- | --- | --- | --- | --- | --- |")
    for c in cells:
        e, s = idle(pathlib.Path(empty) / c), idle(pathlib.Path(seeded) / c)
        pe, ps = parts(e), parts(s)
        for k in ("components", "base", "platform"):
            print(f"| {c} | {k} | {pe[k][0]:.3f} | {pe[k][1] / MIB:.0f} | {ps[k][0]:.3f} | {ps[k][1] / MIB:.0f} |")
        conns = [sum(v["median"] for n, v in x["db_connections"].items() if n != "postgres") for x in (e, s)]
        print(f"| {c} | DB connections | {conns[0]:.0f} | | {conns[1]:.0f} | |")
    print()
    print("| cell | container | empty cores | empty MiB | with data cores | with data MiB |")
    print("| --- | --- | --- | --- | --- | --- |")
    for c in cells:
        e, s = idle(pathlib.Path(empty) / c), idle(pathlib.Path(seeded) / c)
        for name in sorted(e["containers"]):
            if name in BASE:
                continue
            x, y = e["containers"][name]["cgroup"], s["containers"][name]["cgroup"]
            print(f"| {c} | {name} | {x['cores']:.3f} | {x['memory_median'] / MIB:.0f} | {y['cores']:.3f} | {y['memory_median'] / MIB:.0f} |")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
