"""Step 13, E7 (step13-plan.md H5): the business database rolled back to T, the audit database not (protocol 15,
recovery steps 1-3; A98), on a running cell whose audit component has its own database (databases: infra/audit).
The least E7 needs, not the operations runbook's tool:
  1. T: a logical backup of the cell's business database (pg_dump inside be-postgres) and, in the same snapshot
     (pg_export_snapshot, pg_dump --snapshot), per audited component its audit log's highest sequence number; and how
     many of its records infra/audit holds (another database: read right after);
  2. the business goes on for AFTER seconds (the background load produces business and audit records);
  3. freeze (step 2): every component's container stops except infra/audit's (it runs throughout); then per
     component the records produced (its audit log) and transferred (infra/audit holds them), and a fingerprint of
     infra/audit's records;
  4. restore (step 3): the business database dropped and restored from the backup at T, the audit database untouched;
  5. check: the business database is back at T (each audit log's highest sequence number as at T), infra/audit's
     fingerprint is unchanged (not rolled back, nothing transferred lost), and the audit loss per component is the
     records produced after T and not transferred before the freeze (protocol 15 step 9). The load runs on through
     the freeze (runner13.sh stops it after this step), so business goes on after T as it would.
With a pause (the third argument, seconds), infra/audit's container is paused for the last seconds before the
freeze: the transfers fail meanwhile, so some records produced after T are not received when the business database
rolls back, and the loss is not zero (it is unpaused once the executors have stopped).
Steps 4-10 of the recovery (generation, streams, replays, reconciliation, reopening) are not done: the cell stays
frozen and goes down after. One JSON object to <out>.
Usage: cd <conformance> && PYTHONPATH=. uv run python <this> <cell directory> <out file> [after seconds] [pause seconds]
(the pause also from E7_PAUSE, as runner13.sh passes only the first three)"""
import asyncio
import json
import os
import subprocess
import sys
import time

from cells import homes
from cells.spec import Cell

AUDIT_LOGS = "SELECT table_schema FROM information_schema.tables WHERE table_name = 'be_audit_log' ORDER BY 1"


def component_of(c: Cell, schema: str) -> str:
    return next((p for p in c.placed if p.replace("/", "_").replace("-", "_") == schema), schema)


async def read_business(c: Cell, conn, t: dict | None = None) -> dict:
    """Per audited component: its audit log's highest sequence number and the records not yet received; with the
    reading at T, also those of them produced after T (lost with the rollback: the records before T that were not
    received are in the restored log still, and are transferred once it reopens)."""
    out = {}
    for (s,) in await conn.fetch(AUDIT_LOGS):
        comp = component_of(c, s)
        if comp not in c.placed:
            continue
        after = (t or {}).get(comp, {}).get("max_seq", 0)
        top, waiting, lost = await conn.fetchrow(
            f"SELECT coalesce(max(seq), 0), count(*) FILTER (WHERE transfer_state <> 'received'), "
            f"count(*) FILTER (WHERE transfer_state <> 'received' AND seq > $1) FROM \"{s}\".be_audit_log", after)
        out[comp] = {"max_seq": top, "not_received": waiting, **({"not_received_after_t": lost} if t else {})}
    return out


async def business(c: Cell, t: dict | None = None) -> dict:
    conn, _ = await homes.home(c, "erp_sales")  # the business database: every schema but infra/audit's
    try:
        return await read_business(c, conn, t)
    finally:
        await conn.close()


async def backup_at_t(c: Cell) -> dict:
    """The backup and the business reading in one snapshot: what is read is exactly what the backup holds."""
    conn, _ = await homes.home(c, "erp_sales")
    try:
        async with conn.transaction(isolation="repeatable_read", readonly=True):
            snapshot = await conn.fetchval("SELECT pg_export_snapshot()")
            state = await read_business(c, conn)
            pg("pg_dump", "-U", "postgres", "-Fc", f"--snapshot={snapshot}", "-f", "/tmp/e7-t.dump", c.database)
        return state
    finally:
        await conn.close()


async def audit(c: Cell) -> dict:
    """infra/audit's records per source (count and highest source sequence) and a fingerprint of all of them."""
    conn, _ = await homes.home(c, "infra_audit")
    try:
        rows = await conn.fetch("SELECT source, count(*), max(source_seq) FROM infra_audit.audit_record GROUP BY 1 ORDER BY 1")
        fp = await conn.fetchval("SELECT md5(string_agg(source || ':' || source_seq, ',' ORDER BY source, source_seq)) "
                                 "FROM infra_audit.audit_record")
        return {"sources": {s: {"count": n, "max_source_seq": m} for s, n, m in rows}, "fingerprint": fp}
    finally:
        await conn.close()


async def received_after(c: Cell, t: dict) -> dict:
    """Per component: the records infra/audit holds with a source sequence number after T's highest (exact, unlike a
    count read at another moment than T's snapshot)."""
    conn, _ = await homes.home(c, "infra_audit")
    try:
        return {comp: await conn.fetchval("SELECT count(DISTINCT source_seq) FROM infra_audit.audit_record "
                                          "WHERE source = $1 AND source_seq > $2", comp, v["max_seq"])
                for comp, v in t.items()}
    finally:
        await conn.close()


def pg(*args: str) -> str:
    return subprocess.run(["docker", "exec", "be-postgres", *args], check=True, capture_output=True, text=True).stdout


def containers(c: Cell, audit: bool = False) -> list[str]:
    """The cell's containers: every one but infra/audit's, or (audit) only infra/audit's."""
    names = subprocess.run(["docker", "ps", "--filter", f"label=com.docker.compose.project=brickkit-{c.project}",
                            "--format", "{{.Names}}"], check=True, capture_output=True, text=True).stdout.split()
    return [n for n in names if ("-infra-audit-" in n) == audit and "-migration-" not in n]


async def main(c: Cell, out: str, after: float, pause: float = 0) -> None:
    if c.home_of("infra/audit") == ("main", c.database) or c.target != "docker":
        raise SystemExit(f"{c.name}: E7 needs infra/audit in its own database (databases:) on the D row")
    db, r = c.database, {"cell": c.name, "database": c.database, "audit_database": c.home_of("infra/audit")[1]}
    # 1. T
    r["t"] = time.time()
    r["at_t"] = {"business": await backup_at_t(c), "audit": await audit(c)}
    # 2. the business goes on (the audit component paused for its last `pause` seconds)
    r["pause"] = pause
    await asyncio.sleep(after - pause)
    if pause:
        subprocess.run(["docker", "pause", *containers(c, audit=True)], check=True, capture_output=True)
        await asyncio.sleep(pause)
    # 3. freeze: every executor but the audit component stops
    r["freeze"] = time.time()
    stopped = containers(c)
    subprocess.run(["docker", "stop", *stopped], check=True, capture_output=True)
    r["stopped"] = stopped
    if pause:
        subprocess.run(["docker", "unpause", *containers(c, audit=True)], check=True, capture_output=True)
    r["at_freeze"] = {"business": await business(c, r["at_t"]["business"]), "audit": await audit(c),
                      "received_after_t": await received_after(c, r["at_t"]["business"])}
    # 4. restore the business database to T; the audit database is not touched
    t0 = time.time()
    pg("psql", "-U", "postgres", "-d", "postgres", "-c", f'DROP DATABASE "{db}" WITH (FORCE)')
    pg("psql", "-U", "postgres", "-d", "postgres", "-c", f'CREATE DATABASE "{db}"')
    pg("pg_restore", "-U", "postgres", "-d", db, "--exit-on-error", "/tmp/e7-t.dump")
    r["restore_seconds"] = round(time.time() - t0, 1)
    pg("rm", "-f", "/tmp/e7-t.dump")
    r["after_restore"] = {"business": await business(c), "audit": await audit(c)}
    # 5. check
    at_t, frozen, restored = r["at_t"], r["at_freeze"], r["after_restore"]
    r["business_back_at_t"] = {k: v["max_seq"] for k, v in restored["business"].items()} == \
        {k: v["max_seq"] for k, v in at_t["business"].items()}
    r["audit_untouched"] = restored["audit"] == frozen["audit"]
    loss = {}
    for comp, b in frozen["business"].items():
        loss[comp] = {"produced_after_t": b["max_seq"] - at_t["business"].get(comp, {}).get("max_seq", 0),
                      "transferred_after_t": frozen["received_after_t"].get(comp, 0),
                      "lost": b["not_received_after_t"]}
    r["audit_loss"] = loss
    # every record produced after T is either in infra/audit or lost: nothing else
    r["loss_accounted"] = all(v["produced_after_t"] == v["transferred_after_t"] + v["lost"] for v in loss.values())
    r["passed"] = r["business_back_at_t"] and r["audit_untouched"] and r["loss_accounted"]
    open(out, "w").write(json.dumps(r, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps({k: r[k] for k in ("business_back_at_t", "audit_untouched", "loss_accounted", "audit_loss",
                                        "restore_seconds")},
                     ensure_ascii=False))
    if not r["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(main(Cell.load(sys.argv[1]), sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 120,
                     float(sys.argv[4]) if len(sys.argv) > 4 else float(os.environ.get("E7_PAUSE", 0))))
