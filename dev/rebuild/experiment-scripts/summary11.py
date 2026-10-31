#!/usr/bin/env python3
"""Step 11 (suite C): one Markdown summary of a runner11.sh output. Per cell, each fault with its result, what the
fault test timed (faults.jsonl), what the background load saw while the fault and its invariants ran (series.json:
failed requests, the seconds whose confirmations came back 'processing' instead of confirmed, latency), the
invariants' verdict, and the R3, R4 and R5 operations' timed steps; the streams' message and duplicate counts the last
invariants read.
Usage: summary11.py <runner out>... > summary.md"""
import datetime as dt
import json
import pathlib
import re
import sys

# list.order reads an order a random user of the mix created recently: another department's order is not visible
# to the reader and answers 404 (as designed), whatever the fault; those are counted apart
NOT_VISIBLE = "list.order: 404"


def stamp(s: str) -> float:
    return dt.datetime.fromisoformat(s).timestamp()


def hm(t: float) -> str:
    return dt.datetime.fromtimestamp(t).strftime("%H:%M:%S")


def status(out: pathlib.Path) -> tuple[dict, dict]:
    """(cell, stage) -> [begin, end, exit]; (cell, n) -> (fault name, passed?, invariants hold?)"""
    stages, faults = {}, {}
    for line in open(out / "status.log"):
        line = line.strip()
        if m := re.match(r"STAGE (\S+) (\S+) BEGIN (\S+)$", line):
            stages[(m[1], m[2])] = [stamp(m[3]), None, None]
        elif m := re.match(r"STAGE (\S+) (\S+) END exit=(\d+) secs=\d+ (\S+)$", line):
            stages[(m[1], m[2])][1:] = [stamp(m[4]), int(m[3])]
        elif m := re.match(r"CELL (\S+) FAULT (\d+) \((.+)\) (passed|FAILED|not for an S cell)", line):
            faults[(m[1], int(m[2]))] = [m[3], m[4], None]
        elif m := re.match(r"CELL (\S+) INVARIANTS (\d+) (hold|VIOLATED)", line):
            faults[(m[1], int(m[2]))][2] = m[3]
    return stages, faults


def timing(rec: dict) -> str:
    keys = [("up_after", "up {} s"), ("settled_after", "settled {} s"), ("refused_after", "refused after {} s"),
            ("refused_with", "({})"), ("allowed_after", "allowed {} s after the start"),
            ("answered_after", "answering {} s after"), ("reason", "reason {}"), ("outcome", "outcome {}"),
            ("backlog_peak", "outbox backlog peak {}"), ("backlog_peak_at", "{} s after the stop"),
            ("drained_after", "drained {} s after the start"), ("projection_after", "projection caught up {} s after")]
    return ", ".join(f.format(rec[k]) for k, f in keys if k in rec)


def window(series: list, a: float, b: float) -> str:
    rows = [x for x in series if a <= x["unix"] <= b]
    failed = sum(n for x in rows for k, n in (x.get("errors") or {}).items() if not k.startswith(NOT_VISIBLE))
    bad = [x["unix"] for x in rows if any(not k.startswith(NOT_VISIBLE) for k in (x.get("errors") or {}))]
    proc = [x["unix"] for x in rows if (x.get("outcomes") or {}).get("processing")]
    p95 = max((x.get("p95_ms") or 0 for x in rows), default=0)
    parts = [f"{failed} failed" + (f" ({hm(bad[0])}–{hm(bad[-1])})" if bad else "")]
    if proc:
        parts.append(f"processing {proc[-1] - proc[0] + 1:.0f} s from {hm(proc[0])}")
    parts.append(f"max p95 {p95:.0f} ms")
    return "; ".join(parts)


def steps(log: pathlib.Path) -> str:
    lines = [l.strip() for l in open(log, errors="replace") if re.search(r"STEP |REPLACED|SPLIT .*FAILED|BURST exit|\d+ (passed|failed)", l)]
    return "<br>".join(re.sub(r"^\S+ ", "", l)[:160] for l in lines)


def cell(out: pathlib.Path, name: str, stages: dict, faults: dict) -> None:
    d = out / name
    recs = [json.loads(l) for l in open(d / "faults.jsonl")] if (d / "faults.jsonl").exists() else []
    series = json.load(open(d / "series.json")) if (d / "series.json").exists() else []
    load = json.load(open(d / "load.json")) if (d / "load.json").exists() else {}
    print(f"\n## {name}\n")
    if load:
        nv = sum(n for k, n in load["errors"].items() if k.startswith(NOT_VISIBLE))
        print(f"Background load: {load['sent']} sent, {load['ok']} ok, {load['sent'] - load['ok']} failed "
              f"({nv} of them {NOT_VISIBLE}, not visible to the reader); latency p50 {load['latency_ms']['P50']:.1f} ms, "
              f"p95 {load['latency_ms']['P95']:.1f} ms.\n")
    print("| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |")
    print("| --- | --- | --- | --- | --- | --- |")
    for (c, n), (fault, result, inv) in sorted(faults.items(), key=lambda x: x[0][1]):
        if c != name:
            continue
        st, iv = stages.get((name, f"fault-{n}")), stages.get((name, f"invariants-{n}"))
        rec = next((r for r in recs if st and st[0] <= r["at"] <= st[1] + 1), None)
        load_cell = window(series, st[0], (iv[1] if iv and iv[1] else st[1]) + 55) if st and series else ""
        what = timing(rec) if rec else (steps(d / f"fault-{n}.log") if st else "")
        print(f"| {n} | {fault} | {result} | {inv or ''} | {what} | {load_cell} |")
    last = max(d.glob("invariants-*.json"), key=lambda f: f.stat().st_mtime, default=None)
    if last and "measured" in (m := json.load(open(last))):
        print(f"\nStreams after the last fault ({last.name}): messages {m['measured']['stream_messages']}, "
              f"IDs more than once {m['measured']['stream_duplicates']}.")


def main() -> None:
    for arg in sys.argv[1:]:
        out = pathlib.Path(arg)
        stages, faults = status(out)
        print(f"# {out}")
        for name in sorted({c for c, _ in faults}, key=lambda c: min(v[0] for k, v in stages.items() if k[0] == c)):
            cell(out, name, stages, faults)


if __name__ == "__main__":
    main()
