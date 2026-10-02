"""r1-07 (nats-py): the same scenarios as ../go/main.go, through nats-py's JetStream pull API."""
import asyncio
import json
import os
import time
from importlib.metadata import version

import nats
from nats.js.api import AckPolicy, ConsumerConfig, DeliverPolicy, DiscardPolicy, StorageType, StreamConfig
from nats.js.errors import NotFoundError

SEG = "r1py"
STREAM = "BE_" + SEG.upper()
BO = [0.2, 0.5, 1.0]
DAY = 24 * 3600


def durable_name(component: str, subject: str) -> str:  # P12.5
    return component.replace("/", "_") + "__" + subject.replace(".", "_")


def err_or(coro):
    async def run():
        try:
            await coro
            return "ok"
        except Exception as e:  # noqa: BLE001
            return f"ERR {type(e).__name__}: {e}"
    return run()


async def main():
    nc = await nats.connect(os.environ["NATS_URL"])
    js = nc.jetstream()
    jsm = js._jsm if hasattr(js, "_jsm") else nc.jsm()
    try:
        await js.delete_stream(STREAM)
    except NotFoundError:
        pass
    await js.add_stream(StreamConfig(name=STREAM, subjects=[SEG + ".>"], max_age=7 * DAY, max_bytes=1 << 30,
                                     discard=DiscardPolicy.OLD, duplicate_window=600, storage=StorageType.FILE, num_replicas=1))
    print(f"===== nats-py {version('nats-py')}, server {nc.connected_server_version}")

    def cfg(name, subject, **kw):
        return ConsumerConfig(durable_name=name, name=name, filter_subject=subject, ack_policy=AckPolicy.EXPLICIT, **kw)

    async def pub(subject, n):
        for i in range(n):
            await js.publish(subject, json.dumps({"n": i}).encode())

    subj = SEG + ".order.confirmed.v1"
    await pub(subj, 3)
    name = durable_name("crm/opportunity", subj)
    base = dict(deliver_policy=DeliverPolicy.ALL, ack_wait=30, max_ack_pending=256, max_deliver=8,
                inactive_threshold=30 * DAY, backoff=[1, 10, 60, 300, 900, 1800, 3600])
    info = await js.add_consumer(STREAM, cfg(name, subj, **base))
    hy = await err_or(js.add_consumer(STREAM, cfg(durable_name("infra/iam-casdoor", subj), subj, **base)))
    print(f"T1 durable {name!r} created; hyphen variant -> {hy}")
    c = info.config
    print(f"T1 config read back: AckWait={c.ack_wait}s MaxDeliver={c.max_deliver} BackOff={c.backoff} "
          f"InactiveThreshold={c.inactive_threshold}s MaxAckPending={c.max_ack_pending}")
    sub = await js.pull_subscribe_bind(name, STREAM)
    msgs = await sub.fetch(10, timeout=1)
    for m in msgs:
        await m.ack()
    print(f"T2 DeliverAll on first create: fetched {len(msgs)} of 3 pre-existing events")

    print("T3 add_consumer again, identical config:", await err_or(js.add_consumer(STREAM, cfg(name, subj, **base))))
    r = await err_or(js.add_consumer(STREAM, cfg(name, subj, **{**base, "max_deliver": 9})))
    now = (await js.consumer_info(STREAM, name)).config.max_deliver
    print(f"T3 add_consumer again, MaxDeliver 8->9: {r}; MaxDeliver now {now}")
    print("T3 add_consumer again, DeliverPolicy all->new:",
          await err_or(js.add_consumer(STREAM, cfg(name, subj, **{**base, "max_deliver": 9, "deliver_policy": DeliverPolicy.NEW}))))
    print("T3 API surface: update_consumer =", hasattr(jsm, "update_consumer") or hasattr(js, "update_consumer"))

    print("T4a BackOff len 3, MaxDeliver 2:",
          await err_or(js.add_consumer(STREAM, cfg("t4a", SEG + ".t4a", ack_wait=30, max_deliver=2, backoff=BO))))
    await js.add_consumer(STREAM, cfg("t4a2", SEG + ".t4a", ack_wait=30, max_deliver=4, backoff=BO))
    print("T4a stored AckWait when AckWait=30s and BackOff[0]=200ms:", (await js.consumer_info(STREAM, "t4a2")).config.ack_wait)

    advisories = []

    async def on_adv(m):
        a = json.loads(m.data)
        advisories.append(f"{m.subject}: consumer={a['consumer']} stream_seq={a['stream_seq']} deliveries={a['deliveries']}")
    await nc.subscribe(f"$JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES.{STREAM}.>", cb=on_adv)

    async def consume(cons, window, handler, concurrent=False):
        """Record (seconds since first delivery, num_delivered) for each delivery during `window`."""
        s = await js.pull_subscribe_bind(cons, STREAM)
        out, start, end, tasks = [], None, time.monotonic() + window, []
        while time.monotonic() < end:
            try:
                ms = await s.fetch(1, timeout=0.2)
            except asyncio.TimeoutError:
                continue
            for m in ms:
                start = start or time.monotonic()
                out.append(f"+{time.monotonic() - start:.2f}s(n={m.metadata.num_delivered})")
                if concurrent:
                    tasks.append(asyncio.create_task(handler(m, len(out))))
                else:
                    await handler(m, len(out))
        await asyncio.gather(*tasks)
        await s.unsubscribe()
        return out

    async def setup(n, **kw):
        await js.add_consumer(STREAM, cfg(n, f"{SEG}.{n}", **kw))
        await pub(f"{SEG}.{n}", 1)
        return n

    async def noop(m, d):
        pass

    async def nak(m, d):
        await m.nak()

    async def nak_delay(m, d):
        await m.nak(delay=BO[min(d - 1, len(BO) - 1)])

    print("T4b no ack (timeout path), BackOff 200ms,500ms,1s MaxDeliver 4:",
          await consume(await setup("t4b", ack_wait=30, max_deliver=4, backoff=BO), 4, noop))
    print("T4c nak() each time, same BackOff:",
          await consume(await setup("t4c", ack_wait=30, max_deliver=4, backoff=BO), 3, nak))
    t4e = await setup("t4e", ack_wait=30, max_deliver=4)
    print("T4e stored AckWait without BackOff:", (await js.consumer_info(STREAM, t4e)).config.ack_wait)
    print("T4e no BackOff, AckWait 30s, nak(delay=EVENTS_BACKOFF[n-1]):", await consume(t4e, 4, nak_delay))
    await asyncio.sleep(0.5)
    for a in advisories:
        print("T4 advisory", a)

    def slow(every):
        async def h(m, d):
            if d > 1:
                await m.ack()
                return
            end = time.monotonic() + 4
            while time.monotonic() < end:
                await asyncio.sleep(every or 0.1)
                if every:
                    await m.in_progress()
            await m.ack()
        return h

    print("T5a AckWait 2s, slow handler 4s with in_progress every 0.66s (AckWait/3):",
          await consume(await setup("t5a", ack_wait=2, max_deliver=5), 8, slow(0.66), concurrent=True))
    print("T5b control, slow handler 4s, no in_progress:",
          await consume(await setup("t5b", ack_wait=2, max_deliver=5), 8, slow(0), concurrent=True))
    print("T5c AckWait 6s + BackOff [1s,2s,3s], handler 4s, in_progress every 2s (AckWait/3):",
          await consume(await setup("t5c", ack_wait=6, max_deliver=5, backoff=[1, 2, 3]), 9, slow(2), concurrent=True))
    print("T5d same, in_progress every 330ms (BackOff[0]/3):",
          await consume(await setup("t5d", ack_wait=6, max_deliver=5, backoff=[1, 2, 3]), 9, slow(0.33), concurrent=True))
    await nc.close()


asyncio.run(main())
