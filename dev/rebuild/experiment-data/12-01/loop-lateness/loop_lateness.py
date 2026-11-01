"""How late an asyncio timer fires while 300 ms of CPU work runs, by where the work runs: on the event loop, in a
worker thread (asyncio.to_thread) or in a worker process the code starts itself (python -I -c, fed over a pipe).
A 10 ms sleep repeats during the work; the reading is its largest lateness. The modes alternate; each runs REPEAT times.
Standard library only. Usage: python3 loop_lateness.py [repeat]"""
import asyncio
import platform
import statistics
import sys
import time

MS = 300
BURNER = """
import sys, time
for line in sys.stdin:
    x, end = 1, time.perf_counter() + int(line) / 1000
    while time.perf_counter() < end:
        for _ in range(1000):
            x = (x * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    sys.stdout.write("ok\\n")
    sys.stdout.flush()
"""


def burn(ms):
    x, end = 1, time.perf_counter() + ms / 1000
    while time.perf_counter() < end:
        for _ in range(1000):
            x = (x * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF


async def ticker(done):
    late = 0.0
    while not done.is_set():
        t0 = time.perf_counter()
        await asyncio.sleep(0.010)
        late = max(late, time.perf_counter() - t0 - 0.010)
    return late


async def once(mode, worker):
    done = asyncio.Event()
    tick = asyncio.create_task(ticker(done))
    await asyncio.sleep(0.05)  # the ticker runs before the work starts
    if mode == "loop":
        burn(MS)
    elif mode == "thread":
        await asyncio.to_thread(burn, MS)
    else:
        worker.stdin.write(f"{MS}\n".encode())
        await worker.stdin.drain()
        assert await worker.stdout.readline() == b"ok\n"
    done.set()
    return await tick


async def main(repeat):
    worker = await asyncio.create_subprocess_exec(sys.executable, "-I", "-c", BURNER, stdin=asyncio.subprocess.PIPE,
                                                  stdout=asyncio.subprocess.PIPE)
    out = {"loop": [], "thread": [], "process": []}
    for _ in range(repeat):
        for mode in out:
            out[mode].append(await once(mode, worker) * 1000)
    worker.kill()
    print(f"Python {platform.python_version()}, {MS} ms of CPU work, largest lateness of a 10 ms sleep (ms), {repeat} runs each")
    for mode, xs in out.items():
        print(f"{mode:8} median {statistics.median(xs):8.2f}  min {min(xs):8.2f}  max {max(xs):8.2f}  all {[round(x, 2) for x in xs]}")


asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 5))
