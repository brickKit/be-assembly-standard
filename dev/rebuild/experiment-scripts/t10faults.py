#!/usr/bin/env python3
"""Foundations item 1, T10 (foundations-01-transactions-plan.md): faults under load on the probe chain of cell D15-T10.
test/probe-go (two replicas) writes and emits, test/probe-go2 (two replicas) consumes and relays to test/probe-go3
through a work item. Each run loads the chain, injects its fault after checking it hit what it means to (a replica
fewer ready, the bus refusing), waits for the chain to settle and checks the invariants:

  every write answered 201 is seen by go2 exactly once and relayed; go's outbox is all published and its positions
  contiguous per partition and epoch (two replicas number concurrently, CK-EV-02); no work item dead or paused, none
  running past its lease; each cron slot ran once (CK-WK-05, two replicas)

Runs: baseline, kill-go (SIGABRT to one go replica mid-load), kill-go2, bus-down (NATS stopped 120 s mid-load),
takeover (CK-WK-03: the replica holding a long job paused past its lease, the other takes over; resumed, the old
holder's renewal and commit change nothing). Usage (from the assembly project, cell up, BE_ACC_* exported as
cell-chain.sh does): uv run --project tools/be-acceptance/conformance python dev/rebuild/experiment-scripts/t10faults.py
<output directory> [run ...]"""
from __future__ import annotations

import asyncio
import json
import os
import pathlib
import subprocess
import sys
import time
from urllib.parse import urlsplit

R = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(R / "tools/be-acceptance/conformance"))

import asyncpg  # noqa: E402
import httpx  # noqa: E402

from cells import faults  # noqa: E402
from cells.spec import Cell  # noqa: E402

CELL = Cell.load(R / "dev/rebuild/experiment-cells/D15-T10")
GO, GO2 = "test/probe-go", "test/probe-go2"
RATE, LOAD_S = 20, 90


def url(component: str) -> str:
    return f"http://127.0.0.1:{CELL.host_port(component)}"


def admin() -> str:
    return urlsplit(os.environ["BE_ACC_PG_ADMIN"])._replace(path="/" + CELL.database).geturl()


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


async def load(seconds: float, rate: int = RATE) -> list[dict]:
    """Writes with relay at a fixed rate (open loop); each one's answer."""
    out: list[dict] = []

    async def one(c: httpx.AsyncClient) -> None:
        t = time.time()
        try:
            r = await c.post(url(GO) + "/api/probe/write", json={"bytes": 10, "relay": True})
            out.append({"t": t, "code": r.status_code, "id": r.json().get("id") if r.status_code == 201 else None})
        except httpx.HTTPError as e:
            out.append({"t": t, "code": 0, "error": type(e).__name__})

    async with httpx.AsyncClient(timeout=20) as c:
        tasks, t0 = [], time.monotonic()
        for i in range(int(seconds * rate)):
            await asyncio.sleep(max(0.0, t0 + i / rate - time.monotonic()))
            tasks.append(asyncio.create_task(one(c)))
        await asyncio.gather(*tasks)
    return out


async def invariants(c: asyncpg.Connection, writes: list[dict]) -> dict:
    ids = [w["id"] for w in writes if w["code"] == 201]
    events = await c.fetch("SELECT record_id, event_id FROM test_probe_go.be_outbox WHERE record_id = ANY($1)", ids)
    ev = {r["record_id"]: r["event_id"] for r in events}
    seen = {r["event_id"]: (r["n"], r["relayed"]) for r in await c.fetch(
        """SELECT event_id, count(*) AS n, count(*) FILTER (WHERE relayed_at IS NOT NULL) AS relayed
           FROM test_probe_go2.probe_seen WHERE event_id = ANY($1) GROUP BY event_id""", list(ev.values()))}
    gaps = await c.fetch("""SELECT partition, epoch_generation, epoch_timeline, count(*) AS n, min(seq) AS lo, max(seq) AS hi,
            count(DISTINCT seq) AS distinct_seqs FROM test_probe_go.be_outbox WHERE seq IS NOT NULL
            GROUP BY 1, 2, 3""")
    work = await c.fetchrow("""SELECT count(*) FILTER (WHERE state IN ('dead', 'paused')) AS stuck,
            count(*) FILTER (WHERE state = 'running' AND lease_until < now()) AS expired,
            count(*) FILTER (WHERE state IN ('pending', 'retry_wait') AND job = 'probe.relay') AS waiting
            FROM test_probe_go2.be_work_item""")
    cron = await c.fetch("SELECT slot, count(*) AS n FROM test_probe_go.probe_cron GROUP BY slot HAVING count(*) > 1")
    return {
        "answered_201": len(ids), "other_answers": sorted({w["code"] for w in writes if w["code"] != 201}),
        "not_in_outbox": len([i for i in ids if i not in ev]),
        "unpublished": await c.fetchval("SELECT count(*) FROM test_probe_go.be_outbox WHERE published_at IS NULL"),
        "not_seen": len([e for e in ev.values() if e not in seen]),
        "seen_twice": len([e for e, (n, _) in seen.items() if n > 1]),
        "not_relayed": len([e for e, (n, rel) in seen.items() if rel < n]),
        "positions": [dict(g) for g in gaps if g["n"] != g["distinct_seqs"] or g["hi"] - g["lo"] + 1 != g["n"]],
        "work": dict(work), "cron_slots_run_twice": [dict(r) for r in cron],
        "cron_slots": await c.fetchval("SELECT count(DISTINCT slot) FROM test_probe_go.probe_cron"),
    }


def violations(inv: dict) -> list[str]:
    v = []
    for k in ("not_in_outbox", "unpublished", "not_seen", "seen_twice", "not_relayed"):
        if inv[k]:
            v.append(f"{k}: {inv[k]}")
    if inv["positions"]:
        v.append(f"positions not contiguous or numbered twice: {inv['positions']}")
    if inv["work"]["stuck"] or inv["work"]["expired"] or inv["work"]["waiting"]:
        v.append(f"work items: {inv['work']}")
    if inv["cron_slots_run_twice"]:
        v.append(f"cron slots run twice: {inv['cron_slots_run_twice']}")
    return v


async def settle(c: asyncpg.Connection, writes: list[dict], limit: float = 240) -> dict:
    t0 = time.monotonic()
    while True:
        inv = await invariants(c, writes)
        if not violations(inv) or time.monotonic() - t0 > limit:
            inv["settled_s"] = round(time.monotonic() - t0, 1)
            return inv
        await asyncio.sleep(2)


def kill_replica(component: str, n: int) -> dict:
    name = faults.replica(CELL, component, n)
    before = subprocess.run(["docker", "inspect", "-f", "{{.State.StartedAt}}", name], capture_output=True, text=True).stdout.strip()
    subprocess.run(["docker", "exec", name, "kill", "-ABRT", "1"], check=True, capture_output=True)
    down = faults.wait_down(CELL, component)  # the precondition: a replica fewer ready
    t0 = time.monotonic()
    while True:
        after = subprocess.run(["docker", "inspect", "-f", "{{.State.StartedAt}}", name], capture_output=True, text=True).stdout.strip()
        if after != before and faults.healthy(CELL, component):
            break
        if time.monotonic() - t0 > 180:
            raise RuntimeError(f"{name} did not come back")
        time.sleep(0.5)
    return {"killed": name, "started_before": before, "started_after": after, "down_after_s": round(down, 1),
            "back_after_s": round(time.monotonic() - t0, 1)}


async def faulted(fault, at: float) -> tuple[list[dict], dict]:
    """Load for LOAD_S seconds with the fault injected at `at` seconds."""
    async def inject() -> dict:
        await asyncio.sleep(at)
        return await asyncio.to_thread(fault)
    writes, info = await asyncio.gather(load(LOAD_S), inject())
    return writes, info


def bus_down() -> dict:
    subprocess.run(["docker", "stop", "be-nats"], check=True, capture_output=True)
    stopped = time.time()
    time.sleep(120)
    subprocess.run(["docker", "start", "be-nats"], check=True, capture_output=True)
    return {"stopped_at": stopped, "stopped_s": round(time.time() - stopped, 1)}


async def takeover(c: asyncpg.Connection) -> dict:
    """CK-WK-03's takeover half: pause the replica that holds a long job past the lease, the other takes over."""
    async with httpx.AsyncClient(timeout=20) as h:
        r = await h.post(url(GO) + "/api/probe/job", json={"hold_ms": 120000})
        item = r.json()["id"]
    for _ in range(100):
        first = await c.fetchrow("SELECT instance FROM test_probe_go.probe_job_attempts WHERE item = $1 AND attempt = 1", item)
        if first:
            break
        await asyncio.sleep(0.1)
    tried = []
    for n in (1, 2):  # which replica holds it is not known from outside: pause one, see whether the other takes over
        name = faults.replica(CELL, GO, n)
        subprocess.run(["docker", "pause", name], check=True, capture_output=True)
        paused = time.time()
        await asyncio.sleep(45)  # past the 30 s lease
        second = await c.fetchrow("SELECT instance, started_at FROM test_probe_go.probe_job_attempts WHERE item = $1 AND attempt = 2", item)
        tried.append({"paused": name, "taken_over": bool(second)})
        if second:
            subprocess.run(["docker", "unpause", name], check=True, capture_output=True)
            await asyncio.sleep(15)  # the old holder renews (a third of the lease) and finds its claim gone
            break
        subprocess.run(["docker", "unpause", name], check=True, capture_output=True)
    attempts = [dict(a) for a in await c.fetch(
        "SELECT attempt, instance, ended, started_at::text FROM test_probe_go.probe_job_attempts WHERE item = $1 ORDER BY attempt", item)]
    for _ in range(60):
        st = await c.fetchval("SELECT state FROM test_probe_go.be_work_item WHERE id = $1", item)
        if st == "done":
            break
        await asyncio.sleep(1)
    effects = await c.fetchval("SELECT count(*) FROM test_probe_go.probe_job_effects WHERE item = $1", item)
    return {"item": item, "tried": tried, "attempts": attempts, "state": st, "effects": effects, "paused_at": paused,
            "first_instance": first["instance"] if first else None}


async def in_tx(c: asyncpg.Connection) -> dict:
    """Killed in a transaction: writes holding theirs open 2 s (the probe's limit; labelled), one go replica killed
    meanwhile. Some must have been on it (the connection cut or a 5xx, not a refusal): their rows must not exist; the
    others answered 201 and theirs must."""
    async def held(h: httpx.AsyncClient, n: int) -> dict:
        try:
            r = await h.post(url(GO) + "/api/probe/write", json={"bytes": 10, "relay": True, "hold_ms": 2000, "label": f"held-{n}"})
            return {"n": n, "code": r.status_code, "id": r.json().get("id") if r.status_code == 201 else None}
        except httpx.HTTPError as e:
            return {"n": n, "code": 0, "error": type(e).__name__}
    async with httpx.AsyncClient(timeout=20) as h:
        tasks = [asyncio.create_task(held(h, n)) for n in range(12)]
        await asyncio.sleep(1)
        info = await asyncio.to_thread(kill_replica, GO, 2)
        results = await asyncio.gather(*tasks)
    rows = {r["label"]: str(r["id"]) for r in await c.fetch("SELECT label, id FROM test_probe_go.probe_writes WHERE label LIKE 'held-%'")}
    killed = [r for r in results if r["code"] == 0 or r["code"] >= 500]
    return {"fault": info, "results": results, "rows": rows, "killed_in_tx": len(killed),
            "answered_201": len([r for r in results if r["code"] == 201]),
            "refused": len([r for r in results if 400 <= r["code"] < 500]),
            "rolled_back": all(f"held-{r['n']}" not in rows for r in killed),
            "kept": all(rows.get(f"held-{r['n']}") == r["id"] for r in results if r["code"] == 201)}


async def forwarding(c: asyncpg.Connection) -> list[dict]:
    """Killed while forwarding: a backlog built with the bus down, the bus back and one go replica killed at once."""
    subprocess.run(["docker", "stop", "be-nats"], check=True, capture_output=True)
    writes = await load(30)
    backlog = await c.fetchval("SELECT count(*) FROM test_probe_go.be_outbox WHERE published_at IS NULL")
    subprocess.run(["docker", "start", "be-nats"], check=True, capture_output=True)
    await asyncio.sleep(0.5)
    at_kill = await c.fetchval("SELECT count(*) FROM test_probe_go.be_outbox WHERE published_at IS NULL")
    info = await asyncio.to_thread(kill_replica, GO, 2)
    info.update(backlog_before=backlog, unpublished_at_kill=at_kill)
    return writes, info


async def in_job(c: asyncpg.Connection) -> tuple[list[dict], dict]:
    """Killed in a work item: go3 paused so go2's relay calls hang, one go2 replica killed while it holds some."""
    go3 = faults.replica(CELL, "test/probe-go3", 1)
    subprocess.run(["docker", "pause", go3], check=True, capture_output=True)
    loading = asyncio.create_task(load(20))
    held, t0 = [], time.monotonic()
    while time.monotonic() - t0 < 20:  # both replicas hold running relays (calls hanging on the paused go3): kill then
        held = await c.fetch("SELECT holder, count(*) AS n FROM test_probe_go2.be_work_item WHERE job = 'probe.relay' AND state = 'running' GROUP BY holder")
        if len(held) >= 2:
            break
        await asyncio.sleep(0.05)
    info = await asyncio.to_thread(kill_replica, GO2, 2)
    writes = await loading
    subprocess.run(["docker", "unpause", go3], check=True, capture_output=True)
    info.update(running_by_holder=[dict(r) for r in held])
    return writes, info


async def main() -> int:
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    runs = sys.argv[2:] or ["baseline", "kill-go", "kill-go2", "bus-down", "takeover"]
    c = await asyncpg.connect(admin())
    failed = False
    try:
        for run in runs:
            print(f"{now()} {run} begins", flush=True)
            info: dict = {}
            if run == "baseline":
                writes = await load(60)
            elif run == "kill-go":
                writes, info = await faulted(lambda: kill_replica(GO, 2), 30)
            elif run == "kill-go2":
                writes, info = await faulted(lambda: kill_replica(GO2, 2), 30)
            elif run == "bus-down":
                writes, info = await faulted(bus_down, 20)
                info["backlog_during"] = None
            elif run == "in-tx":
                result = await in_tx(c)
                ok = (result["killed_in_tx"] > 0 and result["answered_201"] > 0 and not result["refused"]
                      and result["rolled_back"] and result["kept"])
                (out / f"{run}.json").write_text(json.dumps(result, indent=1, default=str))
                print(f"{now()} {run}: {'ok' if ok else 'VIOLATED'} killed_in_tx={result['killed_in_tx']} "
                      f"answered_201={result['answered_201']} refused={result['refused']} "
                      f"rolled_back={result['rolled_back']} kept={result['kept']}", flush=True)
                failed |= not ok
                continue
            elif run == "forwarding":
                writes, info = await forwarding(c)
                if not info["unpublished_at_kill"]:
                    print(f"{now()} {run}: PRECONDITION the backlog was drained before the kill", flush=True)
                    failed = True
            elif run == "in-job":
                writes, info = await in_job(c)
                if not info["running_by_holder"] or len(info["running_by_holder"]) < 2:
                    print(f"{now()} {run}: PRECONDITION both go2 replicas did not hold running relays at the kill: {info['running_by_holder']}", flush=True)
                    failed = True
            elif run == "takeover":
                result = await takeover(c)
                ok = (result["tried"] and result["tried"][-1]["taken_over"] and result["state"] == "done"
                      and result["effects"] == 1 and len({a["instance"] for a in result["attempts"]}) == 2
                      and result["attempts"][0]["ended"] in ("cancelled", None))
                (out / f"{run}.json").write_text(json.dumps(result, indent=1, default=str))
                print(f"{now()} {run}: {'ok' if ok else 'VIOLATED'} {json.dumps(result, default=str)[:400]}", flush=True)
                failed |= not ok
                continue
            else:
                raise SystemExit(f"unknown run {run}")
            inv = await settle(c, writes)
            v = violations(inv)
            (out / f"{run}.json").write_text(json.dumps({"fault": info, "invariants": inv, "violations": v,
                                                         "writes": writes}, indent=1, default=str))
            print(f"{now()} {run}: {'ok' if not v else 'VIOLATED ' + '; '.join(v)} answered_201={inv['answered_201']} "
                  f"other={inv['other_answers']} settled_s={inv['settled_s']} fault={json.dumps(info, default=str)}", flush=True)
            failed |= bool(v)
    finally:
        await c.close()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
