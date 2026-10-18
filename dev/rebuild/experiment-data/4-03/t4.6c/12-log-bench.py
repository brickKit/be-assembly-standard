"""asyncpg against psqlpy on the shape of a component's write: a transaction that sets its role-like settings locally,
inserts one row and reads it back, then commits; and a plain one-row read. Each driver runs N of each, 8 at a time
over a pool of 8, and the process CPU per operation is reported. Usage: python bench.py <dsn> <n>"""
import asyncio, json, sys, time, uuid

import asyncpg, psqlpy

SCHEMA = "bench_drv_" + uuid.uuid4().hex[:6]
SETUP = [f"CREATE SCHEMA {SCHEMA}", f"CREATE TABLE {SCHEMA}.items (id uuid PRIMARY KEY, n int, note text)"]
SET = f"SET LOCAL search_path = {SCHEMA}"
INSERT = "INSERT INTO items (id, n, note) VALUES ($1, $2, $3)"
SELECT = "SELECT n, note FROM items WHERE id = $1"
NOTE = "x" * 100


async def bench(label, run, n):
    sem = asyncio.Semaphore(8)

    async def one(i):
        async with sem:
            await run(i)

    await asyncio.gather(*(one(i) for i in range(50)))  # warm the pool and the statements
    c0, t0 = time.process_time(), time.perf_counter()
    await asyncio.gather(*(one(i) for i in range(n)))
    return {"op": label, "n": n, "cpu_us_per_op": round((time.process_time() - c0) * 1e6 / n, 1),
            "wall_s": round(time.perf_counter() - t0, 2)}


async def main(dsn, n):
    admin = await asyncpg.connect(dsn)
    for q in SETUP:
        await admin.execute(q)
    out = []
    try:
        ap = await asyncpg.create_pool(dsn, min_size=8, max_size=8)

        async def a_write(i):
            async with ap.acquire() as c, c.transaction():
                await c.execute(SET)
                rid = uuid.uuid4()
                await c.execute(INSERT, rid, i, NOTE)
                await c.fetchrow(SELECT, rid)

        async def a_read(i):
            async with ap.acquire() as c:
                await c.fetchrow(f"SELECT {i} AS n, now() AS at")

        pp = psqlpy.ConnectionPool(dsn=dsn, max_db_pool_size=8)

        async def p_write(i):
            async with pp.acquire() as c:
                async with c.transaction() as tx:
                    await tx.execute(SET)
                    rid = uuid.uuid4()
                    await tx.execute(INSERT, [rid, i, NOTE])
                    await tx.fetch_row(SELECT, [rid])

        async def p_read(i):
            async with pp.acquire() as c:
                await c.fetch_row(f"SELECT {i} AS n, now() AS at")

        for label, fn in (("asyncpg write tx", a_write), ("psqlpy write tx", p_write),
                          ("asyncpg read", a_read), ("psqlpy read", p_read),
                          ("asyncpg write tx (again)", a_write), ("psqlpy write tx (again)", p_write)):
            r = await bench(label, fn, n)
            print(json.dumps(r), flush=True)
        await ap.close()
        pp.close()
    finally:
        await admin.execute(f"DROP SCHEMA {SCHEMA} CASCADE")
        await admin.close()

asyncio.run(main(sys.argv[1], int(sys.argv[2])))
