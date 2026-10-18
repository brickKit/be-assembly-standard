"""CPU and latency of one claim-check upload (PUT 100 KiB + presign a GET) with aioboto3 against the prototype
(aiohttp + its own SigV4), each N times one after the other, then the same with 8 at a time. Every presigned URL of
the first and last upload is fetched and compared. The objects are deleted at the end.
Usage: python bench.py <n> (BE_ACC_S3_URL, BE_ACC_S3_ACCESS_KEY, BE_ACC_S3_SECRET_KEY in the environment)."""
import asyncio, hashlib, json, os, sys, time, uuid

import aioboto3, aiohttp
from botocore.config import Config

sys.path.insert(0, os.path.dirname(__file__))
from sigv4 import Signer

URL, AK, SK = os.environ["BE_ACC_S3_URL"], os.environ["BE_ACC_S3_ACCESS_KEY"], os.environ["BE_ACC_S3_SECRET_KEY"]
BUCKET, PREFIX, BODY = "be-acceptance", f"bench-{uuid.uuid4().hex[:8]}/", os.urandom(100 * 1024)


async def boto_client(stack):
    s = aioboto3.Session()
    return await stack.enter_async_context(s.client("s3", endpoint_url=URL, region_name="us-east-1",
        aws_access_key_id=AK, aws_secret_access_key=SK,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"})))


async def run(label, upload, n, conc):
    sem = asyncio.Semaphore(conc)
    lat, urls = [], []

    async def one(i):
        async with sem:
            t = time.perf_counter()
            urls.append(await upload(f"{PREFIX}{label}/{i}"))
            lat.append(time.perf_counter() - t)

    await one(-1)  # warm: connections, the signing key
    lat.clear(); urls.clear()
    c0 = time.process_time()
    await asyncio.gather(*(one(i) for i in range(n)))
    cpu = time.process_time() - c0
    lat.sort()
    return {"client": label, "concurrency": conc, "n": n, "cpu_ms_per_upload": round(cpu * 1000 / n, 3),
            "p50_ms": round(lat[n // 2] * 1000, 2), "p99_ms": round(lat[int(n * 0.99)] * 1000, 2)}, urls


async def main(n):
    from contextlib import AsyncExitStack
    out = []
    async with AsyncExitStack() as stack, aiohttp.ClientSession() as http:
        s3 = await boto_client(stack)

        async def boto(key):
            await s3.put_object(Bucket=BUCKET, Key=key, Body=BODY, ContentLength=len(BODY), ContentType="application/json")
            return await s3.generate_presigned_url("get_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=604800)

        signer, digest = Signer(URL, "us-east-1", AK), hashlib.sha256(BODY).hexdigest()

        async def proto(key):
            url, headers = signer.put_headers(SK, BUCKET, key, digest, "application/json")
            async with http.put(url, data=BODY, headers=headers) as r:
                if r.status != 200:
                    raise RuntimeError(f"PUT {r.status}: {(await r.text())[:300]}")
            return signer.presign_get(SK, BUCKET, key, 604800)

        for conc in (1, 8):
            for label, fn in (("aioboto3", boto), ("sigv4-aiohttp", proto)):
                res, urls = await run(label, fn, n, conc)
                for u in (urls[0], urls[-1]):
                    async with http.get(u) as r:
                        res.setdefault("fetched", []).append(r.status == 200 and await r.read() == BODY)
                out.append(res)
                print(json.dumps(res), flush=True)
        keys = []
        async for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=PREFIX):
            keys += [{"Key": o["Key"]} for o in page.get("Contents", [])]
        for i in range(0, len(keys), 1000):
            await s3.delete_objects(Bucket=BUCKET, Delete={"Objects": keys[i:i + 1000]})
        print(json.dumps({"deleted": len(keys)}))

asyncio.run(main(int(sys.argv[1])))
