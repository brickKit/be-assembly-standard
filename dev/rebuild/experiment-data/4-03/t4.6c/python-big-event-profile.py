"""Profiles the big-event path of the Python probes: py writes 100 KiB events at a fixed rate, py2 subscribes to py's
stream and receives them (claim check: upload on py's forwarder, fetch on py2). Both run under cProfile, and each
process's CPU seconds are read from /proc around the measured window. Usage:
python profile_big.py <out dir> <rate> <seconds>"""
import asyncio, json, os, pathlib, subprocess, sys

sys.path.insert(0, "<repo>/tools/be-acceptance/conformance")
from besdk.testing import World
from harness import Deployment, Spec, address, free_port, fresh_bus, manifest_version, py_probe

TICK = os.sysconf("SC_CLK_TCK")


def cpu(pid: int) -> float:
    f = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) / TICK


async def main(out: pathlib.Path, rate: int, seconds: int) -> None:
    py = [os.environ["PROBE_PYTHON"], "-m", "probe_py"] if os.environ.get("PROBE_PYTHON") else py_probe()
    profiled = os.environ.get("PROFILE", "1") == "1"  # cProfile inflates the CPU figures: measure without it too
    prof = lambda name: [py[0], "-m", "cProfile", "-o", str(out / f"{name}.prof"), *py[1:]] if profiled else py
    writer = Spec("test/probe-py", "test_probe_py", "test.probe_py", 9601, prof("writer"), manifest_version("py"))
    reader = Spec("test/probe-py2", "test_probe_py2", "test.probe_py2", 9605, prof("reader"), manifest_version("py2"))
    (out / "world").mkdir(exist_ok=True)
    w = await World(out / "world").start()
    d = Deployment(w, await fresh_bus("jetstream", [writer.stream, reader.stream]), out)
    try:
        rport = free_port()
        rd = await d.start(reader, await d.env(reader, {"PROBE_PEER_STREAM": writer.stream}), rport)
        wr = await d.start(writer, await d.env(writer, {"PROBE_PEER_STREAM": reader.stream, **address(reader, rport)}))
        load = "<repo>/tools/be-acceptance/conformance/.bin/load"
        pids = {"writer": wr.proc.pid, "reader": rd.proc.pid}
        before = {k: cpu(p) for k, p in pids.items()}
        res = subprocess.run([load, "-target", wr.url, "-op", "write", "-bytes", str(100 * 1024), "-rate", str(rate),
                              "-warmup", "0s", "-duration", f"{seconds}s", "-out", str(out / "load.json")],
                             capture_output=True, text=True)
        await asyncio.sleep(3)  # the last events arrive
        after = {k: cpu(p) for k, p in pids.items()}
        drv = json.loads((out / "load.json").read_text())
        n = drv.get("ok") or rate * seconds
        print(json.dumps({"load_exit": res.returncode, "ok": drv.get("ok"), "errors": drv.get("errors"),
                          **{f"{k}_cpu_ms_per_event": round((after[k] - before[k]) * 1000 / n, 2) for k in pids}}))
    finally:
        await d.stop()
        await w.stop()

asyncio.run(main(pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])))
