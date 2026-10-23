"""One warm worker: build the engine, render n times, print one JSON line of measurements."""
import json
import resource
import sys
import time

from data import view_model
from engines import ENGINES

engine, n, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
t0, c0 = time.perf_counter(), time.process_time()
render = ENGINES[engine]()
data = view_model()
first = render(data)
cold_wall, cold_cpu = time.perf_counter() - t0, time.process_time() - c0
walls, cpus, same = [], [], True
for _ in range(n):
    w, c = time.perf_counter(), time.process_time()
    pdf = render(data)
    walls.append(time.perf_counter() - w)
    cpus.append(time.process_time() - c)
    same = same and pdf == first
open(out, "wb").write(first)
walls.sort(); cpus.sort()
print(json.dumps({"engine": engine, "n": n, "cold_wall_ms": round(cold_wall * 1000, 1), "cold_cpu_ms": round(cold_cpu * 1000, 1),
                  "p50_wall_ms": round(walls[n // 2] * 1000, 2), "p95_wall_ms": round(walls[int(n * .95)] * 1000, 2),
                  "p50_cpu_ms": round(cpus[n // 2] * 1000, 2), "max_rss_mib": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1),
                  "bytes": len(first), "same_in_process": same}))
