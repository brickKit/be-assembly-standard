#!/usr/bin/env python3
"""Per container of a cell's runner output: cores in each segment (empty/idle.json: no seed data, idle; run/idle.json:
seeded, idle; run/mix.json: the 7/s mix) and, in the mix, CPU seconds per 1000 requests; from
resources.containers.<name>.cgroup. Base services by name, the cell's services by the cell's container prefix.
With --mem also the median memory and anon (memory without page cache) in MiB.
Usage: breakdown.py [--mem] <cell directory>..."""
import json
import pathlib
import sys

MEM = "--mem" in sys.argv
for d in map(pathlib.Path, [a for a in sys.argv[1:] if a != "--mem"]):
    print(f"== {d.name}")
    for seg, f in (("empty idle", "empty/idle.json"), ("seeded idle", "run/idle.json"), ("mix", "run/mix.json"),
                   ("mix 2", "run-2/mix.json")):
        if seg == "mix 2" and not (d / f).exists():  # the second mix only when the runner had RATE2 (step 10, B5)
            continue
        r = json.loads((d / f).read_text())["resources"]
        for name, c in sorted(r["containers"].items()):
            g = c["cgroup"]
            per = f" {g['cpu_seconds_per_1000']:.1f} s/1000" if "cpu_seconds_per_1000" in g else ""
            mem = f" {g['memory_median'] / 2**20:.0f} MiB {g['anon_median'] / 2**20:.0f} anon" if MEM else ""
            print(f"{seg:11} {name[:48]:48} {g['cores']:.3f} cores{per}{mem}")
