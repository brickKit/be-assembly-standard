"""Step 13: a Markdown summary of runner13.sh outputs (steps 4-6). Per cell: each step and invariants check as the
runner logged it, the invariants' violations, the background load (sent, failed, latency; the errors by kind, the
list.order 404s apart as summary11.py does: they are unrelated to any fault), what each fault test measured
(faults.jsonl) with the load's failed requests in the two minutes after it, the work holders seen per schema, the
requests per replica (replicas only), and E7's result.
Usage: python3 summary13.py <runner13 out>...   (each holds status.log and one directory per cell)"""
import collections
import json
import pathlib
import re
import sys

UNRELATED = re.compile(r"^list\.order: 404 NOT_FOUND$")


def load(p: pathlib.Path):
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return None


def kind(err: str) -> str:
    """An error without its order or delivery ID."""
    return re.sub(r"/[0-9a-f-]{36}", "/<id>", re.sub(r'"http://127\.0\.0\.1:\d+', '"', err))


def cell(out: pathlib.Path, d: pathlib.Path, status: list[str]) -> list[str]:
    name = d.name
    lines = [f"### {name} ({out.name})", ""]
    for s in status:
        if f"CELL {name} " in s and re.search(r"STEP \d+|INVARIANTS|FAILED", s):
            lines.append(f"- {s.split(f'CELL {name} ', 1)[1]}")
    for f in sorted(d.glob("invariants-*.json")):
        inv = load(f) or {}
        bad = {k: v for k, v in inv.items() if k != "measured" and v}
        if bad:
            lines.append(f"- {f.stem}: " + "; ".join(f"{k}: {v[:3]}" for k, v in bad.items()))
    lj = load(d / "load.json")
    if lj:
        errs = collections.Counter()
        for e, n in (lj.get("errors") or {}).items():
            errs[kind(e)] += n
        unrelated = sum(n for e, n in errs.items() if UNRELATED.match(e))
        lat = lj.get("latency_ms", {})
        lines.append(f"- load: sent {lj['sent']}, ok {lj['ok']}, failed {lj['sent'] - lj['ok'] - unrelated} "
                     f"(+{unrelated} list.order 404); p50 {lat.get('P50')} ms, p95 {lat.get('P95')} ms, p99 {lat.get('P99')} ms")
        for e, n in errs.most_common():
            if not UNRELATED.match(e):
                lines.append(f"  - {n} × {e[:160]}")
    series = load(d / "series.json") or []
    for line in (d / "faults.jsonl").read_text().splitlines() if (d / "faults.jsonl").exists() else []:
        f = json.loads(line)
        t0 = f.get("at") or f.get("kill_at") or f.get("restart_at") or f.get("stop_at")
        failed = sum(s["sent"] - s["ok"] for s in series if t0 and t0 <= s["unix"] < t0 + 120)
        shown = {k: v for k, v in f.items() if k not in ("at",)}
        lines.append(f"- fault: {json.dumps(shown, ensure_ascii=False)}; load failures in the 120 s after: {failed}")
    holders = d / "holders.txt"
    if holders.exists():
        for h in holders.read_text().splitlines():
            if h.startswith("# ") and h.count("holders") and not h.startswith("# 1 "):
                m = re.match(r"# (\S+): (\d+) holders", h)
                if m and int(m.group(2)) > 1:
                    lines.append(f"- holders {m.group(1)}: {m.group(2)} processes")
    rc = d / "replica-counts.txt"
    if rc.exists():
        rows = [r for r in rc.read_text().splitlines() if not r.startswith("#") and "-migration-" not in r]
        groups = collections.defaultdict(list)
        for r in rows:
            unit = r.split(":")[0]
            groups[re.sub(r"-(\d+|[a-z0-9]{9,10}-[a-z0-9]{5})$", "", unit)].append(r)
        for g, rs in sorted(groups.items()):
            if len(rs) > 1:
                lines.append(f"- replicas {g}: " + " | ".join(r.split(": ", 1)[1] for r in rs))
    e7 = load(d / "e7.json")
    if e7:
        loss = {k: v for k, v in e7["audit_loss"].items() if any(v.values())}
        lines.append(f"- E7: after {round(e7['freeze'] - e7['t'])} s (audit paused {e7.get('pause', 0)} s); back at T "
                     f"{e7['business_back_at_t']}, audit untouched {e7['audit_untouched']}, loss accounted "
                     f"{e7.get('loss_accounted')}; restore {e7['restore_seconds']} s; {json.dumps(loss)}")
    return lines + [""]


def main() -> None:
    for arg in sys.argv[1:]:
        out = pathlib.Path(arg)
        status = (out / "status.log").read_text().splitlines() if (out / "status.log").exists() else []
        for d in sorted(p for p in out.iterdir() if p.is_dir() and (p / "bring-up").exists()):
            print("\n".join(cell(out, d, status)))


if __name__ == "__main__":
    main()
