"""Summarizes a T2c run (raw.jsonl of run.sh): per step and mode, the medians over every rep of the wall seconds, the
CPU seconds (this process plus the worker process), and the request coroutine's lateness while the step ran: its p99
and max (median over the reps) and the worst max of all reps; the spread is the per-process medians' lowest and
highest wall, as a percentage of the overall median. Usage: python3 summary.py <raw.jsonl>"""
import json
import statistics
import sys

data: dict[tuple[str, str], list[list[dict]]] = {}
last: dict[tuple[str, str], int] = {}
for line in open(sys.argv[1]):
    o = json.loads(line)
    k = (o["step"], o["mode"])
    runs = data.setdefault(k, [])
    if o["rep"] == 0:  # a new process
        runs.append([])
    runs[-1].append(o)

med = statistics.median
print(f"{'step':5} {'mode':12} {'reps':>4} {'wall ms':>8} {'spread %':>13} {'cpu ms':>7} {'p99 late':>9} {'max late':>9} "
      f"{'worst max':>9}")
for step in ("seal", "copy", "read"):
    for mode in ("loop", "thread", "process", "thread-chunk"):
        runs = data.get((step, mode), [])
        xs = [x for r in runs for x in r]
        if not xs:
            continue
        wall = med(x["wall_s"] for x in xs)
        per = [med(x["wall_s"] for x in r) for r in runs]
        cpu = med(x["process_cpu_s"] + x["worker_cpu_s"] for x in xs)
        print(f"{step:5} {mode:12} {len(xs):4} {wall * 1000:8.1f} {(min(per) / wall - 1) * 100:+6.1f}/"
              f"{(max(per) / wall - 1) * 100:+5.1f} {cpu * 1000:7.1f} {med(x['late_p99_ms'] for x in xs):9.2f} "
              f"{med(x['late_max_ms'] for x in xs):9.2f} {max(x['late_max_ms'] for x in xs):9.2f}")
