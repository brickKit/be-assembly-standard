"""T2c: where be-sdk-python's tiering does its CPU work (Catalog.compute): on the event loop (the reference: what not
to do), in a thread (asyncio.to_thread, the SDK's default now), or in a worker process the module owns (a
ProcessPoolExecutor of one forkserver worker, started before the work: the rows are pickled to it and the result back).
The work is the SDK's own functions on rows as the database driver gives them (the long simulation's class: every
column type): the seal's table_sum, the copy's canonical rows and Parquet write, the read's Parquet read and canonical
rows. Meanwhile a "request" coroutine wakes every 2 ms (what another member of a shell would serve): its lateness is the
event loop's stall. Requirement served: a shell hosts several Python members on one event loop; a tiering job of one
must not hold up the others' requests and deadlines (assembly project's merge safety; protocol 17).

Usage: python -I bench.py <mode> <rows> <reps> ; modes: loop, thread, process, and thread-chunk (a thread, the read
turning the file into values a batch at a time: a second round of measurement). Prints one JSON line per step and rep:
wall seconds, the CPU seconds of this process (a thread's included) and of the worker process, and the request coroutine's lateness (count, p50, p99,
max, in ms) while the step ran."""
from __future__ import annotations

import asyncio
import concurrent.futures
import datetime as dt
import json
import multiprocessing
import random
import sys
import time
import uuid
from decimal import Decimal

from besdk.tiering import parquet
from besdk.tiering import rows as canonical
from besdk.tiering.catalog import table_sum
from besdk.tiering.classes import Table
from besdk.tiering.rows import (BOOL, BYTEA, DATE, INT2, INT4, INT8, JSONB, NUMERIC, TEXT, TEXT_ARRAY, TIMESTAMPTZ,
                                UUID)

TABLE = Table("docs", {"id": UUID, "grp": TEXT, "rev": INT4, "code": TEXT, "note": TEXT, "amount": NUMERIC, "qty": INT8,
                       "small": INT2, "flag": BOOL, "day": DATE, "attrs": JSONB, "blob": BYTEA, "tags": TEXT_ARRAY,
                       "closed_at": TIMESTAMPTZ, "created_at": TIMESTAMPTZ}, pk="id")
TICK = 0.002


def make_rows(n: int, seed: int = 7) -> list[dict]:
    """n rows as asyncpg gives them (numeric and jsonb as text, as the SDK selects them), deterministic."""
    r = random.Random(seed)
    base = dt.datetime(2025, 1, 1, tzinfo=dt.timezone.utc)
    out = []
    for i in range(n):
        out.append({"id": uuid.UUID(int=r.getrandbits(128)), "grp": f"g{r.randrange(4)}", "rev": r.randrange(1, 9),
                    "code": f"D-{i:08d}", "note": None if r.random() < 0.3 else f"call +34 600 {r.randrange(10**6)}",
                    "amount": str(Decimal(f"{r.randrange(10**6)}.{r.randrange(10**4):04d}")),
                    "qty": r.randrange(1 << 53), "small": r.randrange(65536) - 32768, "flag": r.random() < 0.5,
                    "day": None if r.random() < 0.3 else dt.date(2020, 1, 1) + dt.timedelta(days=r.randrange(2000)),
                    "attrs": '{"n": [1, "é"]}', "blob": r.randbytes(r.randrange(256)),
                    "tags": [f"t{r.randrange(9)}", "Ä"], "closed_at": base - dt.timedelta(seconds=r.randrange(10**7)),
                    "created_at": base - dt.timedelta(days=4000)})
    return out


# the steps, as the SDK calls them through compute: plain top-level functions (a worker process needs to pickle them)
def seal(rows: list[dict]):
    return table_sum(TABLE.columns, TABLE.key_columns(), rows)


def copy(rows: list[dict]):
    keys = [(canonical.pk_bytes(TABLE.columns, TABLE.key_columns(), r).decode(), canonical.row_bytes(TABLE.columns, r))
            for r in rows]
    return len(keys), parquet.write(TABLE, rows)


def read(raw: bytes):
    return len([canonical.row(TABLE.columns, r) for r in parquet.read(TABLE, raw)])


def read_chunked(raw: bytes):
    """The read step with the file turned into Python values a batch of 1024 rows at a time (thread-chunk): each call
    into pyarrow holds the GIL only for one batch, not a whole column."""
    import io

    import pyarrow.parquet as pq

    n = 0
    names = sorted(TABLE.columns)
    for b in pq.ParquetFile(io.BytesIO(raw)).iter_batches(batch_size=1024):
        cols = {c: [parquet._back(TABLE.columns[c], v) for v in b.column(c).to_pylist()] for c in names}
        n += len([canonical.row(TABLE.columns, {c: cols[c][i] for c in names}) for i in range(b.num_rows)])
    return n


def timed(fn, *args):
    """In whichever thread or process runs it: the result and this thread's CPU seconds."""
    t = time.thread_time()
    out = fn(*args)
    return out, time.thread_time() - t


async def request_loop(stop: asyncio.Event, lateness: list[float]) -> None:
    loop = asyncio.get_running_loop()
    while not stop.is_set():
        due = loop.time() + TICK
        await asyncio.sleep(TICK)
        lateness.append((loop.time() - due) * 1000)


def pct(xs: list[float], q: float) -> float:
    if not xs:
        return 0.0
    s = sorted(xs)
    return s[min(len(s) - 1, int(q * len(s)))]


async def main(mode: str, n: int, reps: int) -> None:
    rows = make_rows(n)
    pool = None
    if mode == "process":
        pool = concurrent.futures.ProcessPoolExecutor(1, mp_context=multiprocessing.get_context("forkserver"))
        await asyncio.get_running_loop().run_in_executor(pool, time.sleep, 0)  # started before the work

    async def run(fn, *args):
        if mode == "loop":
            return timed(fn, *args)
        if mode in ("thread", "thread-chunk"):
            return await asyncio.to_thread(timed, fn, *args)
        return await asyncio.get_running_loop().run_in_executor(pool, timed, fn, *args)

    raw = (await run(copy, rows))[0][1]  # warm-up, and the file the read step reads
    await run(seal, rows)
    await run(read, raw)
    for rep in range(reps):
        rd = read_chunked if mode == "thread-chunk" else read
        for step, fn, arg in (("seal", seal, rows), ("copy", copy, rows), ("read", rd, raw)):
            lateness: list[float] = []
            stop = asyncio.Event()
            ticker = asyncio.create_task(request_loop(stop, lateness))
            await asyncio.sleep(0.05)
            lateness.clear()
            if pool is not None:  # the worker's whole CPU: unpickling the rows and pickling the result included
                wcpu0 = await asyncio.get_running_loop().run_in_executor(pool, time.process_time)
            cpu0, w0 = time.process_time(), time.perf_counter()
            await run(fn, arg)
            wall, cpu = time.perf_counter() - w0, time.process_time() - cpu0
            worker_cpu = 0.0
            if pool is not None:
                worker_cpu = await asyncio.get_running_loop().run_in_executor(pool, time.process_time) - wcpu0
            stop.set()
            await ticker
            print(json.dumps({"mode": mode, "rows": n, "rep": rep, "step": step, "wall_s": round(wall, 4),
                              "process_cpu_s": round(cpu, 4),
                              "worker_cpu_s": round(worker_cpu, 4),
                              "ticks": len(lateness), "late_p50_ms": round(pct(lateness, 0.5), 2),
                              "late_p99_ms": round(pct(lateness, 0.99), 2),
                              "late_max_ms": round(max(lateness, default=0.0), 2)}), flush=True)
    if pool is not None:
        pool.shutdown()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], int(sys.argv[2]), int(sys.argv[3])))
