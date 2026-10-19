"""Per-transaction overhead with asyncpg: a short write transaction (BEGIN, the SDK's set_config of six settings, one
INSERT, COMMIT) three ways: A as the SDK does it (pool reset on release), B without the reset, C without the reset and
with BEGIN and set_config in one round trip. Client CPU (this process) and server CPU (the PostgreSQL container's
cgroup) per transaction, 8 at once. Usage: python bench.py <admin dsn> <postgres cgroup cpu.stat path> [n]"""
import asyncio, os, resource, sys, time, uuid
import asyncpg

DSN, CPUSTAT = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 4000
SETTINGS = "SELECT set_config('search_path', 'txbench', true), set_config('statement_timeout', '5000', true), " \
           "set_config('lock_timeout', '2000', true), set_config('idle_in_transaction_session_timeout', '10000', true), " \
           "set_config('application_name', 'txbench', true), set_config('timezone', 'UTC', true)"

def server_cpu():
    for line in open(CPUSTAT):
        if line.startswith("usage_usec"):
            return int(line.split()[1]) / 1e6

def client_cpu():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime

async def noreset(conn):
    pass

async def one(pool, mode):
    async with pool.acquire() as c:
        if mode == "C":
            await c.execute("BEGIN ISOLATION LEVEL READ COMMITTED; " + SETTINGS)
        else:
            await c.execute("BEGIN ISOLATION LEVEL READ COMMITTED")
            await c.execute(SETTINGS)
        await c.execute("INSERT INTO txbench.t (id, v) VALUES ($1, $2)", uuid.uuid4(), "x" * 100)
        await c.execute("COMMIT")

async def run(mode):
    kw = {} if mode == "A" else {"reset": noreset}
    pool = await asyncpg.create_pool(DSN, min_size=8, max_size=8, **kw)
    for _ in range(200):
        await one(pool, mode)
    q = asyncio.Queue()
    for _ in range(N):
        q.put_nowait(None)
    async def worker():
        while not q.empty():
            q.get_nowait()
            await one(pool, mode)
    c0, s0, t0 = client_cpu(), server_cpu(), time.perf_counter()
    await asyncio.gather(*(worker() for _ in range(8)))
    c1, s1, t1 = client_cpu(), server_cpu(), time.perf_counter()
    await pool.close()
    return (c1 - c0) / N * 1e3, (s1 - s0) / N * 1e3, (t1 - t0) / N * 1e3

async def main():
    a = await asyncpg.connect(DSN)
    await a.execute("CREATE SCHEMA IF NOT EXISTS txbench; CREATE TABLE IF NOT EXISTS txbench.t (id uuid PRIMARY KEY, v text)")
    await a.close()
    for rnd in range(3):
        for mode in ("A", "B", "C"):
            c, s, w = await run(mode)
            print(f"round {rnd} {mode}: client {c:.3f} ms/tx, server {s:.3f} ms/tx, wall {w:.3f} ms/tx (8 at once)", flush=True)
    a = await asyncpg.connect(DSN)
    await a.execute("DROP SCHEMA txbench CASCADE")
    await a.close()

asyncio.run(main())
