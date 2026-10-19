"""Idle CPU of an object storage that holds many objects: fill N objects of 100 KiB, then idle, reading the container's
CPU every second; the prefix is emptied at the end. Usage: idlefull.py <container> <out.json> [--objects 20000]
[--idle 300]. Same environment as stbench.py."""
import argparse, asyncio, json, os, pathlib, statistics, subprocess, sys, time
sys.path.insert(0, str(pathlib.Path(os.environ["BE_ACC_CONFORMANCE"])))
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from harness import empty_prefixes, ensure_bucket, need  # noqa: E402
from stbench import cpu_usec, sample_cpu  # noqa: E402

PREFIX = "stidle/"


async def main() -> None:
    a = argparse.ArgumentParser(); a.add_argument("container"); a.add_argument("out")
    a.add_argument("--objects", type=int, default=20000); a.add_argument("--idle", type=float, default=300)
    o = a.parse_args()
    import aioboto3
    cid = subprocess.check_output(["docker", "inspect", "-f", "{{.Id}}", o.container], text=True).strip()
    await ensure_bucket(); await empty_prefixes([PREFIX])
    body = os.urandom(102400); slots = asyncio.Semaphore(16)
    t0 = time.monotonic()
    async with aioboto3.Session().client("s3", endpoint_url=need("BE_ACC_S3_URL"), region_name="us-east-1",
                                         aws_access_key_id=need("BE_ACC_S3_ACCESS_KEY"),
                                         aws_secret_access_key=need("BE_ACC_S3_SECRET_KEY")) as s3:
        async def one(i):
            async with slots:
                await s3.put_object(Bucket="be-acceptance", Key=f"{PREFIX}{i:08d}", Body=body)
        await asyncio.gather(*(one(i) for i in range(o.objects)))
    filled = time.monotonic() - t0
    cpu: list = []; stop = asyncio.Event()
    t1 = time.monotonic(); task = asyncio.create_task(sample_cpu(cid, cpu, stop))
    await asyncio.sleep(o.idle); stop.set(); await task
    gone = await empty_prefixes([PREFIX])
    rel = [(t - t1, c) for t, c in cpu]
    pathlib.Path(o.out).write_text(json.dumps({"container": o.container, "objects": o.objects, "fill_s": filled,
                                               "cpu": rel, "deleted": gone}))
    cs = [c for _, c in rel]
    print(f"{o.container}: filled {o.objects} in {filled:.0f} s; idle {o.idle:.0f} s CPU mean {statistics.mean(cs):.3f} "
          f"median {statistics.median(cs):.3f} max {max(cs):.2f}, seconds over 1 core {sum(c > 1 for c in cs)}; deleted {gone}")


asyncio.run(main())
