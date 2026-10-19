"""Object storage upload timeline: idle, then an open-loop PUT rate, with the storage container's CPU read every second.

Usage: stbench.py <container> <out.json> [--rate 50] [--seconds 300] [--idle 60] [--size 102400] [--concurrency 32]
Needs BE_ACC_S3_URL, BE_ACC_S3_ACCESS_KEY, BE_ACC_S3_SECRET_KEY (bucket be-acceptance, prefix stbench/; the prefix is
emptied before and after). Run with the be-acceptance conformance environment (aioboto3, harness)."""
import argparse
import asyncio
import json
import os
import pathlib
import statistics
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(os.environ["BE_ACC_CONFORMANCE"])))
from harness import empty_prefixes, ensure_bucket, need  # noqa: E402

PREFIX = "stbench/"


def cpu_usec(cid: str) -> int:
    for line in open(f"/sys/fs/cgroup/system.slice/docker-{cid}.scope/cpu.stat"):
        if line.startswith("usage_usec"):
            return int(line.split()[1])
    raise RuntimeError("no usage_usec")


async def sample_cpu(cid: str, out: list, stop: asyncio.Event) -> None:
    last_t, last_u = time.monotonic(), cpu_usec(cid)
    while not stop.is_set():
        try:
            await asyncio.wait_for(stop.wait(), 1.0)
        except TimeoutError:
            pass
        t, u = time.monotonic(), cpu_usec(cid)
        out.append((t, (u - last_u) / 1e6 / (t - last_t)))
        last_t, last_u = t, u


async def main() -> None:
    a = argparse.ArgumentParser()
    a.add_argument("container"); a.add_argument("out")
    a.add_argument("--rate", type=float, default=50); a.add_argument("--seconds", type=float, default=300)
    a.add_argument("--idle", type=float, default=60); a.add_argument("--size", type=int, default=102400)
    a.add_argument("--concurrency", type=int, default=32)
    o = a.parse_args()
    import aioboto3

    cid = subprocess.check_output(["docker", "inspect", "-f", "{{.Id}}", o.container], text=True).strip()
    await ensure_bucket()
    await empty_prefixes([PREFIX])
    body = os.urandom(o.size)
    cpu: list = []
    stop = asyncio.Event()
    t0 = time.monotonic()
    sampler = asyncio.create_task(sample_cpu(cid, cpu, stop))
    await asyncio.sleep(o.idle)
    puts: list = []
    slots = asyncio.Semaphore(o.concurrency)
    async with aioboto3.Session().client("s3", endpoint_url=need("BE_ACC_S3_URL"), region_name="us-east-1",
                                         aws_access_key_id=need("BE_ACC_S3_ACCESS_KEY"),
                                         aws_secret_access_key=need("BE_ACC_S3_SECRET_KEY")) as s3:
        async def one(i: int, due: float) -> None:
            async with slots:
                await s3.put_object(Bucket="be-acceptance", Key=f"{PREFIX}{i:08d}", Body=body)
            puts.append((due - t0, (time.monotonic() - due) * 1000))  # from when it was due: open loop

        start = time.monotonic()
        n = int(o.rate * o.seconds)
        tasks = []
        for i in range(n):
            due = start + i / o.rate
            if (d := due - time.monotonic()) > 0:
                await asyncio.sleep(d)
            tasks.append(asyncio.create_task(one(i, due)))
        await asyncio.gather(*tasks)
    stop.set()
    await sampler
    gone = await empty_prefixes([PREFIX])
    cpu_rel = [(t - t0, c) for t, c in cpu]
    pathlib.Path(o.out).write_text(json.dumps({"container": o.container, "rate": o.rate, "size": o.size,
                                               "idle": o.idle, "puts": puts, "cpu": cpu_rel, "deleted": gone}))
    lat = [p[1] for p in puts]
    idle_cpu = [c for t, c in cpu_rel if t < o.idle]
    print(f"{o.container}: {len(lat)} puts, p50 {statistics.median(lat):.1f} ms, p99 "
          f"{sorted(lat)[int(len(lat) * .99)]:.1f} ms, max {max(lat):.1f} ms; idle CPU median "
          f"{statistics.median(idle_cpu):.3f} max {max(idle_cpu):.3f}; deleted {gone}")


if __name__ == "__main__":
    asyncio.run(main())
