#!/usr/bin/env python3
"""Step 8 perf rounds: the tables of record 8-01 from each cell's run/idle.json and run/mix.json.
Resources are the cgroup view (what the container costs, page cache included), and for the components also the
process view (resident memory, no page cache: steadier between passes); parts: the component containers
(alone or shells), the base resources (PostgreSQL, NATS, object storage, Casdoor) and the platform (Docker).
Usage: r8-summary.py <cell-dir>... (each holding run/idle.json and run/mix.json, or the archived idle.json and mix.json)"""
import json
import pathlib
import sys

BASE = ("be-postgres", "be-nats", "be-rustfs", "be-seaweedfs", "be-casdoor")
MIB = 1024 * 1024


def parts(res: dict) -> dict:
    out = {"components": [0.0, 0.0], "base": [0.0, 0.0]}
    for name, c in res["containers"].items():
        g = c["cgroup"]
        key = "base" if name in BASE else "components"
        out[key][0] += g["cores"]
        out[key][1] += g["memory_median"]
    p = res["platform"]
    out["platform"] = [p["cores"], p["memory_median"]]
    return out


def each(res: dict) -> dict:
    return {name: (c["cgroup"]["cores"], c["cgroup"]["memory_median"]) for name, c in res["containers"].items()}


def short(name: str) -> str:
    for cut in ("brickkit-d8-s-", "brickkit-d8-h-", "brickkit-d8-x-"):
        name = name.replace(cut, "")
    return name.rsplit("-", 4)[0] if name.startswith(("erp-", "mdm-", "infra-", "be-go", "be-py")) else name


def at(d: str) -> pathlib.Path:
    """A round's cell output (run/idle.json) or its archived copy (idle.json beside the logs)."""
    return pathlib.Path(d) / "run" if (pathlib.Path(d) / "run").is_dir() else pathlib.Path(d)


def main(dirs: list[str]) -> None:
    print("| cell | part | idle cores | idle MiB | mix cores | mix MiB | mix CPU s per 1000 requests |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for d in dirs:
        run = at(d)
        idle, mix = (json.loads((run / f).read_text()) for f in ("idle.json", "mix.json"))
        pi, pm = parts(idle["resources"]), parts(mix["resources"])
        n = mix["resources"]["requests"]
        for k in ("components", "base", "platform"):
            per = pm[k][0] * mix["resources"]["elapsed"] / n * 1000
            print(f"| {mix['cell']} | {k} | {pi[k][0]:.3f} | {pi[k][1] / MIB:.0f} | {pm[k][0]:.3f} | {pm[k][1] / MIB:.0f} | {per:.1f} |")
    print()
    print("| cell | components: process RSS, idle MiB | mix MiB |")
    print("| --- | --- | --- |")
    for d in dirs:
        run = at(d)
        idle, mix = (json.loads((run / f).read_text()) for f in ("idle.json", "mix.json"))
        rss = [sum(c["process"]["memory_median"] for k, c in x["resources"]["containers"].items() if k not in BASE) / MIB
               for x in (idle, mix)]
        print(f"| {mix['cell']} | {rss[0]:.0f} | {rss[1]:.0f} |")
    print()
    print("| cell | container | idle cores | idle MiB | mix cores | mix MiB |")
    print("| --- | --- | --- | --- | --- | --- |")
    for d in dirs:
        run = at(d)
        idle, mix = (json.loads((run / f).read_text()) for f in ("idle.json", "mix.json"))
        ei, em = each(idle["resources"]), each(mix["resources"])
        for name in sorted(em):
            if name in BASE:
                continue
            print(f"| {mix['cell']} | {short(name)} | {ei[name][0]:.3f} | {ei[name][1] / MIB:.0f} | {em[name][0]:.3f} | {em[name][1] / MIB:.0f} |")
    print()
    print("| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max | DB connections (component and shell roles, median) |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for d in dirs:
        mix = json.loads((at(d) / "mix.json").read_text())
        dr, ops, c = mix["driver"], mix["driver"]["mix"]["ops"], mix["completion"]["issue_to_completed_ms"]
        lat = dr["latency_ms"]
        conns = sum(v["median"] for k, v in mix["resources"]["db_connections"].items() if k != "postgres")
        row = " | ".join(f"{ops[o]['latency_ms']['P95']:.1f}" for o in ("list", "order", "confirm", "deliver", "bill"))
        print(f"| {mix['cell']} | {dr['sent']} / {dr['ok']} | {lat['P50']:.1f} | {lat['P95']:.1f} | {lat['P99']:.1f} | "
              f"{lat['Max']:.1f} | {row} | {c['P50']} / {c['P95']} / {c['Max']} | {conns:.0f} |")


if __name__ == "__main__":
    main(sys.argv[1:])
