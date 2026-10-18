"""Profiles the Python probe as a caller: py (under cProfile) -> py2 over HTTP, at a fixed rate, then stops it
cleanly so cProfile writes its stats. Usage: python profile_py.py <out dir> <surface> <rate> <seconds>"""
import asyncio, json, pathlib, subprocess, sys

sys.path.insert(0, "/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance")
from besdk.testing import World
from harness import Deployment, Spec, address, free_port, fresh_bus, manifest_version, py_probe

async def main(out: pathlib.Path, surface: str, rate: int, seconds: int) -> None:
    py = py_probe()
    callee = Spec("test/probe-py2", "test_probe_py2", "test.probe_py2", 9605, py, manifest_version("py2"))
    caller = Spec("test/probe-py", "test_probe_py", "test.probe_py", 9601,
                  [py[0], "-m", "cProfile", "-o", str(out / f"caller-{surface}.prof"), *py[1:]], manifest_version("py"))
    (out / "world").mkdir(exist_ok=True)
    w = await World(out / "world").start()
    d = Deployment(w, await fresh_bus("jetstream", [caller.stream, callee.stream]), out)
    try:
        cport = free_port()
        await d.start(callee, await d.env(callee, {}), cport)
        r = await d.start(caller, await d.env(caller, {"PROBE_PEER_STREAM": callee.stream, **address(callee, cport)}))
        load = "/home/zhijie/Desktop/github/be-assembly-standard/tools/be-acceptance/conformance/.bin/load"
        res = subprocess.run([load, "-target", r.url, "-op", "call", "-surface", surface, "-inner", "echo",
                              "-bytes", "1024", "-rate", str(rate), "-warmup", "3s", "-duration", f"{seconds}s",
                              "-out", str(out / f"load-{surface}.json")], capture_output=True, text=True)
        print("load exit", res.returncode, res.stderr[-500:])
        drv = json.loads((out / f"load-{surface}.json").read_text())
        print(surface, "hop", drv.get("hop_ms"), "throughput", drv.get("throughput"), "errors", drv.get("errors"))
    finally:
        await d.stop()
        await w.stop()

asyncio.run(main(pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])))
