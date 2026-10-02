"""r1-04 (asyncpg): prepared-statement cache x SET LOCAL ROLE / search_path on one pooled connection.

One pool with exactly one physical connection (min_size=max_size=1), logged in as the NOINHERIT
shell role. Every "member transaction" starts with SET LOCAL ROLE <r> + SET LOCAL search_path TO <s>
(P10.2), then runs the same SQL text. Members alternate a, b, a, b on that one connection.
Run once with the default statement cache and once with statement_cache_size=0.
"""
import asyncio
import os
import sys
import time

import asyncpg

DSN = os.environ["PG_DSN"]  # postgres://shell:shell@127.0.0.1:PORT/r1db
MEMBERS = {"a": ("ra", "a"), "b": ("rb", "b")}


PREFIX = False  # mode "prefix": cache on, every member's SQL text starts with /* be:<member> */


class Tagged:
    """What an SDK Tx would do in mode "prefix": make the cache key (= SQL text) differ per member."""

    def __init__(self, conn, member):
        self._c, self._p = conn, f"/* be:{member} */ "

    def fetchrow(self, sql, *a):
        return self._c.fetchrow(self._p + sql, *a)

    def fetchval(self, sql, *a):
        return self._c.fetchval(self._p + sql, *a)


async def member_tx(pool, member, fn):
    role, schema = MEMBERS[member]
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(f'SET LOCAL ROLE "{role}"')
            await conn.execute(f'SET LOCAL search_path TO "{schema}"')
            return await fn(Tagged(conn, member) if PREFIX else conn)


async def run_case(pool, name, order, fn):
    print(f"--- {name}")
    for m in order:
        try:
            r = await member_tx(pool, m, fn)
            print(f"  [{m}] OK   {r}")
        except Exception as e:  # noqa: BLE001 - we want to see every failure class
            print(f"  [{m}] ERR  {type(e).__name__}: {e} (sqlstate={getattr(e, 'sqlstate', None)})")


async def outside(pool):
    async with pool.acquire() as conn:
        r = await conn.fetchrow("SELECT pg_backend_pid() AS pid, current_user AS usr, current_setting('search_path') AS sp")
        return dict(r)


async def main(cache_size: int, prefix: bool):
    global PREFIX
    PREFIX = prefix
    print(f"===== asyncpg {asyncpg.__version__}, statement_cache_size={cache_size}, per-member SQL prefix={prefix}")
    pool = await asyncpg.create_pool(DSN, min_size=1, max_size=1, statement_cache_size=cache_size)
    print("before:", await outside(pool))
    alt = ["a", "b", "a", "b"]

    await run_case(pool, "S1 same shape SELECT id, v FROM widget WHERE id=$1", alt,
                   lambda c: c.fetchrow("SELECT id, v, current_schema() AS s FROM widget WHERE id = $1", 1))
    await run_case(pool, "S1 same shape UPDATE ... RETURNING", alt,
                   lambda c: c.fetchval("UPDATE widget SET v = v || '+' WHERE id = $1 RETURNING v", 1))
    await run_case(pool, "S2 different result type: SELECT id, payload FROM besdk_thing", alt,
                   lambda c: c.fetchrow("SELECT id, payload FROM besdk_thing WHERE id = $1", 1))
    await run_case(pool, "S2 different result type: SELECT * FROM besdk_thing", alt,
                   lambda c: c.fetchrow("SELECT * FROM besdk_thing WHERE id = $1", 1))
    await run_case(pool, "S3 same listed types, b has extra col: SELECT id, payload FROM besdk_same", alt,
                   lambda c: c.fetchrow("SELECT id, payload FROM besdk_same WHERE id = $1", 1))
    await run_case(pool, "S3 SELECT * FROM besdk_same (column count differs)", alt,
                   lambda c: c.fetchrow("SELECT * FROM besdk_same WHERE id = $1", 1))

    # S4: parameter type inferred at first Parse (text in a, jsonb in b)
    counter = iter(range(100, 200))

    async def ins(c):
        i = next(counter)
        return await c.fetchval("INSERT INTO besdk_thing (id, payload) VALUES ($1, $2) RETURNING payload::text", i, '{"k":1}')
    await run_case(pool, "S4 INSERT INTO besdk_thing (id, payload) VALUES ($1,$2) (param text vs jsonb)", alt, ins)

    print("--- S5 isolation: role ra with search_path b")
    try:
        async with pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute('SET LOCAL ROLE "ra"')
                await conn.execute('SET LOCAL search_path TO "b"')
                print("  unexpected:", await conn.fetchrow("SELECT * FROM widget"))
    except Exception as e:  # noqa: BLE001
        print(f"  ERR (expected) {type(e).__name__}: {e}")

    print("--- S6 NOINHERIT: shell login without SET ROLE reads a.widget")
    try:
        async with pool.acquire() as conn:
            print("  unexpected:", await conn.fetchrow("SELECT * FROM a.widget"))
    except Exception as e:  # noqa: BLE001
        print(f"  ERR (expected) {type(e).__name__}: {e}")

    print("--- S7 leak check after commit:", await outside(pool))
    try:
        await member_tx(pool, "a", lambda c: c.fetchval("SELECT 1/0"))
    except Exception as e:  # noqa: BLE001
        print(f"  (forced error: {type(e).__name__})")
    print("--- S7 leak check after rollback:", await outside(pool))

    # micro benchmark: one tx = SET LOCAL x2 + one parameterised query, alternating members
    n = 2000
    t0 = time.perf_counter()
    for i in range(n):
        await member_tx(pool, "ab"[i % 2], lambda c: c.fetchrow("SELECT id, v FROM widget WHERE id = $1", 1))
    dt = time.perf_counter() - t0
    print(f"--- bench: {n} alternating member tx in {dt:.2f}s = {dt / n * 1e3:.3f} ms/tx")
    await pool.close()


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]), len(sys.argv) > 2 and sys.argv[2] == "prefix"))
