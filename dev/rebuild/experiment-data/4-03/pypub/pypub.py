"""Python publish cost: one publisher publishing in order (as the forwarder does), process CPU and wall time a message,
for three ways of waking the readers. Usage: pypub.py [--n 5000] [--rounds 3]. Needs BE_SDK_TEST_PG_ADMIN; uses the
be-sdk-python test bus (schema py_bus_test in the test database) and deletes what it publishes."""
import argparse
import asyncio
import json
import os
import resource
import time
import uuid

from urllib.parse import urlsplit

from besdk.events.core import Message
from besdk.events.pgqueue import WAKE_CHANNEL, Transport


def cpu() -> float:
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime


async def in_statement(t: Transport, m: Message) -> None:  # the NOTIFY in the inserting statement (a13)
    await t.pool.execute(f"""WITH m AS (INSERT INTO {t.t('be_bus_message')} (msg_id, subject, headers, data)
        VALUES ($1, $2, $3::jsonb, $4) ON CONFLICT (msg_id) WHERE msg_id IS NOT NULL DO NOTHING RETURNING 1)
        SELECT pg_notify($5, $2) FROM m""", m.id or None, m.subject, json.dumps(m.headers), m.data, WAKE_CHANNEL)


async def second_statement(t: Transport, m: Message) -> None:  # a second statement on the publish path (a14)
    status = await t.pool.execute(f"""INSERT INTO {t.t('be_bus_message')} (msg_id, subject, headers, data)
        VALUES ($1, $2, $3::jsonb, $4) ON CONFLICT (msg_id) WHERE msg_id IS NOT NULL DO NOTHING""",
                                  m.id or None, m.subject, json.dumps(m.headers), m.data)
    if not status.endswith(" 0"):
        await t.pool.execute("SELECT pg_notify($1, $2)", WAKE_CHANNEL, m.subject)


async def notifier(t: Transport, m: Message) -> None:  # the transport's notifier, off the publish path (a15)
    await t.publish(m)


DEDICATED: dict = {}


async def dedicated(t: Transport, m: Message) -> None:  # the same, the NOTIFY on a connection of its own (no pool)
    status = await t.pool.execute(f"""INSERT INTO {t.t('be_bus_message')} (msg_id, subject, headers, data)
        VALUES ($1, $2, $3::jsonb, $4) ON CONFLICT (msg_id) WHERE msg_id IS NOT NULL DO NOTHING""",
                                  m.id or None, m.subject, json.dumps(m.headers), m.data)
    if not status.endswith(" 0"):
        DEDICATED["q"].put_nowait(m.subject)


async def dedicated_loop(conn, q: asyncio.Queue) -> None:
    while True:
        subject = await q.get()
        await conn.execute("SELECT pg_notify($1, $2)", WAKE_CHANNEL, subject)
        q.task_done()


async def main() -> None:
    a = argparse.ArgumentParser(); a.add_argument("--n", type=int, default=5000); a.add_argument("--rounds", type=int, default=3)
    o = a.parse_args()
    import pgtest  # tests/pgtest.py, on the path when run from the SDK's tests directory
    u = urlsplit(pgtest.admin_dsn(pgtest.DATABASE))
    t = await Transport.connect(u._replace(scheme="pgqueue", query="schema=py_bus_test&sslmode=disable").geturl(), "pypub")
    subject = f"pypub.s{uuid.uuid4().hex[:8]}.bench"
    kinds = {"in-statement": in_statement, "second-statement": second_statement, "notifier": notifier,
             "dedicated-conn": dedicated}
    import asyncpg
    conn = await asyncpg.connect(**t._args)  # noqa: SLF001 - a connection outside the pool, in the same database
    DEDICATED["q"] = asyncio.Queue(4096)
    loop_task = asyncio.create_task(dedicated_loop(conn, DEDICATED["q"]))
    try:
        for r in range(o.rounds):
            for name, fn in kinds.items():
                await asyncio.sleep(0.5)
                c0, w0 = cpu(), time.perf_counter()
                for _ in range(o.n):
                    await fn(t, Message(subject, {"ce-id": str(uuid.uuid4())}, b"x" * 100))
                while not t._notes.empty():  # the notifier's backlog belongs to the cost
                    await asyncio.sleep(0.001)
                await DEDICATED["q"].join()
                c1, w1 = cpu(), time.perf_counter()
                print(f"round {r + 1} {name:16} cpu {1000 * (c1 - c0) / o.n:.3f} ms/msg  wall {1000 * (w1 - w0) / o.n:.3f} ms/msg")
    finally:
        loop_task.cancel()
        await conn.close()
        await t.pool.execute(f"DELETE FROM {t.t('be_bus_message')} WHERE subject = $1", subject)
        await t.close()


asyncio.run(main())
