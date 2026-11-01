"""Step 13, E1 and E2: which process holds each running work item, sampled every two seconds until stopped (SIGINT or
SIGTERM). A finished item keeps no holder (be-sdk-go work/run.go clears it), so sampling the running ones is the way
to see that every replica of a component claimed work. One line per sample and holder: unix time, schema, holder
(<component ID>/<instance ID>, one per process), running items. Run from the conformance tools (cells/homes.py: a
moved schema is read too). At the end a summary line per schema: the distinct holders seen and the samples each.
Usage: cd <conformance> && uv run python <this> <cell directory> <out file>"""
import asyncio
import collections
import signal
import sys
import time

from cells import homes
from cells.spec import Cell

SCHEMAS = "SELECT table_schema FROM information_schema.tables WHERE table_name = 'be_work_item' ORDER BY 1"


async def main(cell: Cell, out: str) -> None:
    stop = asyncio.Event()
    for s in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_running_loop().add_signal_handler(s, stop.set)
    seen = collections.defaultdict(collections.Counter)
    conn = await homes.checks(cell)
    try:
        schemas = [s for (s,) in await conn.fetch(SCHEMAS)]
        with open(out, "a") as f:
            while not stop.is_set():
                t = int(time.time())
                for s in schemas:
                    for holder, n in await conn.fetch(
                            f"SELECT holder, count(*) FROM \"{s}\".be_work_item WHERE state = 'running' GROUP BY 1"):
                        f.write(f"{t} {s} {holder} {n}\n")
                        seen[s][holder] += 1
                f.flush()
                try:
                    await asyncio.wait_for(stop.wait(), 2)
                except asyncio.TimeoutError:
                    pass
            for s, holders in sorted(seen.items()):
                f.write(f"# {s}: {len(holders)} holders: " + ", ".join(f"{h}={n}" for h, n in holders.most_common()) + "\n")
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main(Cell.load(sys.argv[1]), sys.argv[2]))
