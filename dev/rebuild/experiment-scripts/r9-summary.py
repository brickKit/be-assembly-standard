#!/usr/bin/env python3
"""Step 9: the tables of record 9-01 from each cell's runner9.sh output: empty/idle.json (no seed data, idle),
run/idle.json and run/mix.json (seeded, idle and the 7/s mix). Every row's cost is split the same way:
  components  D, P: the cell's containers; K: its pods (pod:*); L: its processes (proc:*); LD, LP: both
  base        PostgreSQL, NATS, object storage, Casdoor: Docker containers in every row, or the K row's pods in
              namespace be-base when the cell has `base: cluster` (base:*, step 10 B7)
  platform    D: Docker's daemons; P: Podman's helpers (conmon, pasta, ...); K: the minikube node minus the cell's pods
              and the base pods (control plane, kubelet, CNI, kube-proxy); L: the go run / uv wrappers and the brickkit
              up session;
              LD: Docker's daemons, LP: Podman's helpers
  local       LD, LP: the go run / uv wrappers and the brickkit up session of the processes on this machine
  docker      the Docker daemons that serve the base resources in the P, K, L and LP rows (D, LD: that is the platform)
Memory: the cgroup's median with page cache (MiB) and without it (anon + shmem, "anon MiB"; processes: RssAnon +
RssShmem). Usage: r9-summary.py <runner9 output>/<cell>..."""
import json
import pathlib
import re
import sys

BASE = ("be-postgres", "be-nats", "be-rustfs", "be-seaweedfs", "be-casdoor", "be-pgbouncer")
MIB = 1024 * 1024


def part(figs: list[dict]) -> tuple[float, float, float | None]:
    """cores, memory MiB and anon MiB; the platforms' readings are process RSS (no page cache), so no anon of their own"""
    anon = sum(f["anon_median"] for f in figs if "anon_median" in f) / MIB if any("anon_median" in f for f in figs) else None
    return sum(f["cores"] for f in figs), sum(f["memory_median"] for f in figs) / MIB, anon


def parts(res: dict, row: str) -> dict[str, tuple[float, float, float]]:
    containers, units, platforms = res["containers"], res.get("units") or {}, res.get("platforms") or {}
    out = {"base": part([c["cgroup"] for n, c in containers.items() if n in BASE]
                        + [u for n, u in units.items() if n.startswith("base:")]),
           "components": part([c["cgroup"] for n, c in containers.items() if n not in BASE]
                              + [u for n, u in units.items() if n.startswith(("pod:", "proc:"))])}
    if row in ("D", "LD"):
        out["platform"] = part([platforms["docker"]])
    elif row in ("P", "LP"):
        out["platform"] = part([platforms["podman"]])
    elif row == "K":
        node, pods = part([units["minikube-node"]]), out["components"]
        bp = part([u for n, u in units.items() if n.startswith("base:")]) if any(n.startswith("base:") for n in units) \
            else (0.0, 0.0, 0.0)
        out["platform"] = (node[0] - pods[0] - bp[0], node[1] - pods[1] - bp[1], node[2] - pods[2] - bp[2])
    else:
        out["platform"] = part([units["local-platform"]])
    if row in ("LD", "LP"):
        out["local"] = part([units["local-platform"]])
    if row not in ("D", "LD"):
        out["docker"] = part([platforms["docker"]])
    return out


def row_of(cell: str) -> str:
    """The row is the letters before the step number: D9-S is D, LD9-S is LD."""
    return re.match(r"[A-Z]+", cell).group(0)


def seg_file(d: pathlib.Path, runner: str, archived: str) -> pathlib.Path:
    """A segment's file in the runner's output (empty/idle.json, run/idle.json, run/mix.json) or as the experiment
    data archives it, flat in the cell's directory (empty-idle.json, idle.json, mix.json)."""
    return d / runner if (d / runner).exists() else d / archived


def main(dirs: list[str]) -> None:
    print("| cell | segment | part | cores | MiB | anon MiB | CPU s per 1000 requests |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for d in dirs:
        d = pathlib.Path(d)
        for seg, f in (("empty idle", seg_file(d, "empty/idle.json", "empty-idle.json")),
                       ("seeded idle", seg_file(d, "run/idle.json", "idle.json")), ("mix", seg_file(d, "run/mix.json", "mix.json")),
                       ("mix 2", d / "run-2" / "mix.json")):
            if seg == "mix 2" and not f.exists():  # the second mix only when the runner had RATE2 (step 10, B5)
                continue
            if not f.exists():
                print(f"| {d.name} | {seg} | (missing) | | | | |")
                continue
            x = json.loads(f.read_text())
            res = x["resources"]
            for k, (cores, mem, anon) in parts(res, row_of(x["cell"])).items():
                per = f"{cores * res['elapsed'] / res['requests'] * 1000:.1f}" if seg.startswith("mix") and res["requests"] else ""
                a = "—" if anon is None else f"{anon:.0f}"
                print(f"| {x['cell']} | {seg} | {k} | {cores:.3f} | {mem:.0f} | {a} | {per} |")
    print()
    print("| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for f, label in [(x, s) for d in dirs for x, s in ((seg_file(pathlib.Path(d), "run/mix.json", "mix.json"), ""),
                                                       (pathlib.Path(d) / "run-2" / "mix.json", " (mix 2)"))]:
        if not f.exists():
            continue
        mix = json.loads(f.read_text())
        dr, ops, c = mix["driver"], mix["driver"]["mix"]["ops"], mix["completion"]["issue_to_completed_ms"]
        lat = dr["latency_ms"]
        row = " | ".join(f"{ops[o]['latency_ms']['P95']:.1f}" for o in ("list", "order", "confirm", "deliver", "bill"))
        print(f"| {mix['cell']}{label} | {dr['sent']} / {dr['ok']} | {lat['P50']:.1f} | {lat['P95']:.1f} | {lat['P99']:.1f} | "
              f"{lat['Max']:.1f} | {row} | {c['P50']} / {c['P95']} / {c['Max']} |")


if __name__ == "__main__":
    main(sys.argv[1:])
