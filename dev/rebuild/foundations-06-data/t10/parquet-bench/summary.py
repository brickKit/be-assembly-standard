"""Summarizes a T2b run (raw.jsonl of run.sh): per candidate, the medians of write and read (wall and CPU seconds) over
every timed pair, the spread (the per-process medians' lowest and highest, as a percentage of the overall median), the
file's size, the peak memory, and whether the file carries the logical types be-sdk-go writes (UUID on u_uuid, JSON on
j_jsonb and ta_text_array). Usage: python3 summary.py <raw.jsonl>"""
import json
import re
import statistics
import sys

procs: dict[str, list[list[dict]]] = {}
fit: dict[str, str] = {}
rss: dict[str, list[int]] = {}
for line in open(sys.argv[1]):
    o = json.loads(line)
    c = o["candidate"]
    if "fit" in o:
        procs.setdefault(c, []).append([])
        fit[c] = o["fit"]["schema"]
    elif "max_rss_kib" in o:
        rss.setdefault(c, []).append(o["max_rss_kib"])
    else:
        procs[c][-1].append(o)


def spread(runs: list[list[dict]], k: str) -> tuple[float, float, float]:
    allv = [x[k] for r in runs for x in r]
    med = statistics.median(allv)
    per = [statistics.median(x[k] for x in r) for r in runs]
    return med, (min(per) / med - 1) * 100, (max(per) / med - 1) * 100


print(f"{'candidate':9} {'pairs':>5} {'write ms':>9} {'spread %':>13} {'write cpu':>9} {'read ms':>8} {'spread %':>13} "
      f"{'read cpu':>8} {'MB':>6} {'rss MB':>7}  logical types")
for c in sorted(procs):
    runs = procs[c]
    w, wl, wh = spread(runs, "write_s")
    rd, rl, rh = spread(runs, "read_s")
    wc = statistics.median(x["write_cpu_s"] for r in runs for x in r)
    rc = statistics.median(x["read_cpu_s"] for r in runs for x in r)
    size = runs[0][0]["bytes"] / 1e6
    s = fit[c]
    lines = {m.group(1): ln for ln in s.splitlines() if (m := re.search(r"field_id=-?\d+ (\w+)", ln))}
    types = {"u_uuid UUID": "(UUID)" in lines.get("u_uuid", ""),
             "j_jsonb JSON": "(JSON)" in lines.get("j_jsonb", ""),
             "ta_text_array JSON": "(JSON)" in lines.get("ta_text_array", "")}
    ok = ", ".join(f"{k}={'yes' if v else 'NO'}" for k, v in types.items())
    print(f"{c:9} {sum(map(len, runs)):5} {w * 1000:9.1f} {wl:+6.1f}/{wh:+5.1f} {wc * 1000:9.1f} {rd * 1000:8.1f} "
          f"{rl:+6.1f}/{rh:+5.1f} {rc * 1000:8.1f} {size:6.2f} {max(rss[c]) / 1024:7.0f}  {ok}")
