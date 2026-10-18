"""Watches checkall.sh every 30 s and prints a line only when there is a problem, every 5 minutes (progress), or at the
end. Problems: a stage ending with a non-zero exit, a failed cell or an implausible measurement in the last stage,
no output growing for 15 minutes, the script gone without its END line, cells left running after the end.

    python checkall_watch.py <out> <campaign.yaml>"""
import json
import os
import pathlib
import subprocess
import sys
import time

sys.path.insert(0, "/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance/cells")
import watch  # noqa: E402

POLL, PROGRESS, STALL = 30, 300, 900
LIMIT_ERRORS = ("OUTBOUND_LIMIT", "SERVICE_BUSY", "DEADLINE_EXCEEDED")


def expected_limit(o: dict, load: str, problems: list[str], fine_at_50: bool) -> str:
    """The category of an expected limit, or "" when the problems need a look. Only at 200/s: anything at 50/s is a
    problem (the queue defect of 2026-10-18 showed there)."""
    if load != "200":
        return ""
    errors = o["driver"].get("errors") or {}
    cores = max((v["process"]["cores"] for k, v in o["resources"]["containers"].items() if k.startswith("brickkit-")),
                default=0)
    if cores >= 0.9 and all(any(e in k for e in LIMIT_ERRORS) for k in errors):
        return "CPU 跑满"
    if not errors and fine_at_50 and all(x.startswith("events arrive") for x in problems):
        return "订阅逐条处理的上限"
    return ""


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def tail(path: pathlib.Path, n: int = 3) -> str:
    try:
        lines = [x for x in path.read_text(errors="replace").splitlines() if x.strip()]
    except OSError:
        return ""
    return " | ".join(x[:200] for x in lines[-n:])


def main(out: str, spec: str) -> int:
    root, total = pathlib.Path(out), watch.planned(spec)
    status, logs, meas = root / "status.log", root / "logs", root / "measure"
    for _ in range(60):
        if (root / "pid").exists():
            break
        time.sleep(1)
    pid = int((root / "pid").read_text())
    seen_lines, seen_files, by_key = 0, set(), {}
    clean50: set[str] = set()  # operations whose 50/s measurement had nothing to report
    limits: dict[str, int] = {}  # expected limits by category: counted, not woken for
    if "--from-now" in sys.argv:  # re-armed: what was there is already reported; earlier runs still count as history
        seen_lines = len(status.read_text().splitlines()) if status.exists() else 0
        for f in [*meas.glob("**/result.json"), *meas.glob("**/failed.txt")]:
            seen_files.add(f)
            if f.name == "result.json":
                try:
                    o = json.loads(f.read_text())
                except ValueError:
                    continue
                k = watch.key(f, meas)[1]
                by_key.setdefault(k, []).append(watch.figures(o))
                if f.parent.name == "50" and not watch.anomalies(o, "50", [], f.parent.parent.name):
                    clean50.add(k.rsplit("/", 1)[0])
    last_size, last_growth, last_progress, problems = -1, time.time(), time.time(), 0
    while True:
        lines = status.read_text().splitlines() if status.exists() else []
        for line in lines[seen_lines:]:
            if " END exit=" in line and " END exit=0 " not in line:
                problems += 1
                name = line.split()[2]
                n = line.split()[1].split("/")[0]
                print(f"PROBLEM stage {line.split()[1]} {name} failed ({line.split('END ')[1]}): "
                      f"{tail(logs / f'{n}-{name}.log')}", flush=True)
        seen_lines = len(lines)
        # in the order they were written: a 50/s result must be seen before its 200/s one (the paths sort 200 first)
        for f in sorted({*meas.glob("**/result.json"), *meas.glob("**/failed.txt")} - seen_files, key=lambda p: p.stat().st_mtime):
            seen_files.add(f)
            if f.name == "failed.txt":
                problems += 1
                print(f"PROBLEM cell failed {f.parent.relative_to(meas)}: {tail(f, 1)}", flush=True)
                continue
            try:
                o = json.loads(f.read_text())
            except ValueError:
                continue
            run, k = watch.key(f, meas)
            found = watch.anomalies(o, f.parent.name, by_key.get(k, []), f.parent.parent.name)
            if f.parent.name == "50":
                clean50.add(k.rsplit("/", 1)[0]) if not found else clean50.discard(k.rsplit("/", 1)[0])
            if found:
                category = expected_limit(o, f.parent.name, found, k.rsplit("/", 1)[0] in clean50)
                if category:
                    limits[category] = limits.get(category, 0) + 1
                else:
                    problems += 1
                    print(f"PROBLEM {run}/{k}: {'; '.join(found)}", flush=True)
            by_key.setdefault(k, []).append(watch.figures(o))
        size = sum(p.stat().st_size for p in root.rglob("*") if p.is_file())
        if size != last_size:
            last_size, last_growth = size, time.time()
        now = time.time()
        current = next((x for x in reversed(lines) if " BEGIN " in x), "")
        if lines and lines[-1].startswith("END"):
            ps = subprocess.run(["docker", "ps", "--format", "{{.Names}}"], capture_output=True, text=True).stdout
            left = [x for x in ps.split() if x.startswith("brickkit-d-")]
            ends = [x for x in lines if " END exit=" in x]
            failed = [x.split()[2] for x in ends if " END exit=0 " not in x]
            print(f"ENDED: {len(ends)}/{ends[0].split()[1].split('/')[1] if ends else '?'} stages, failed {failed or 'none'}; measurements "
                  f"{len([p for p in seen_files if p.name == 'result.json'])}; problems {problems}; expected limits {limits or 'none'}"
                  + (f"; cells still running {left}" if left else ""), flush=True)
            return 0
        if not alive(pid):
            print(f"PROBLEM the script is gone without its END line; last: {lines[-1] if lines else '-'}", flush=True)
            return 1
        if now - last_growth > STALL:
            print(f"PROBLEM no output for {int((now - last_growth) / 60)} min; at {current}", flush=True)
            last_growth = now
        if now - last_progress > PROGRESS:
            stage = current.split()[1:3] if current else ["-", "-"]
            m = len([p for p in seen_files if p.name == "result.json"])
            extra = f"; measurements {m}/{total - 15}" if "measure" in current else ""
            print(f"progress: stage {stage[0]} {stage[1]}{extra}; problems {problems}; expected limits {limits or 'none'}",
                  flush=True)
            last_progress = now
        time.sleep(POLL)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
