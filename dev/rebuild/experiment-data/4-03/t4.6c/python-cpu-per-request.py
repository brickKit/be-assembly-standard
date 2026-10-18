"""CPU milliseconds per request of the Python probe as a caller (py -> py2 over HTTP or gRPC) at a fixed rate,
read from /proc around the measured window. Usage: python cpu_per_request.py <out dir> <label> <surface> <rate> <seconds>"""
import asyncio, json, os, pathlib, subprocess, sys

sys.path.insert(0, "<repo>/tools/be-acceptance/conformance")
from besdk.testing import World
from harness import Deployment, Spec, address, free_port, fresh_bus, manifest_version, py_probe

TICK = os.sysconf("SC_CLK_TCK")

def cpu(pid: int) -> float:
    f = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) / TICK  # utime, stime

async def main(out: pathlib.Path, label: str, surface: str, rate: int, seconds: int) -> None:
    py = py_probe() if not os.environ.get("KEEP_VENV") else [
        "<repo>/tools/be-acceptance/probes/py/.venv/bin/python", "-m", "probe_py"]
    callee = Spec("test/probe-py2", "test_probe_py2", "test.probe_py2", 9605, py, manifest_version("py2"))
    caller = Spec("test/probe-py", "test_probe_py", "test.probe_py", 9601, py, manifest_version("py"))
    (out / "world").mkdir(exist_ok=True)
    w = await World(out / "world").start()
    d = Deployment(w, await fresh_bus("jetstream", [caller.stream, callee.stream]), out)
    try:
        cport = free_port()
        await d.start(callee, await d.env(callee, {}), cport)
        r = await d.start(caller, await d.env(caller, {"PROBE_PEER_STREAM": callee.stream, **address(callee, cport)}))
        load = "<repo>/tools/be-acceptance/conformance/.bin/load"
        common = ["-target", r.url, "-op", "call", "-surface", surface, "-inner", "echo", "-bytes", "1024", "-rate", str(rate)]
        subprocess.run([load, *common, "-warmup", "1s", "-duration", "3s", "-out", "/dev/null"], capture_output=True)
        before = cpu(r.proc.pid)
        res = subprocess.run([load, *common, "-warmup", "0s", "-duration", f"{seconds}s", "-out", str(out / "load.json")],
                             capture_output=True, text=True)
        used = cpu(r.proc.pid) - before
        drv = json.loads((out / "load.json").read_text())
        ok = drv.get("ok") or 0
        print(json.dumps({"label": label, "surface": surface, "rate": rate, "ok": ok, "cpu_ms_per_request":
                          round(1000 * used / max(ok, 1), 2), "hop_p50": drv["hop_ms"]["P50"], "hop_p99": drv["hop_ms"]["P99"],
                          "errors": drv.get("errors")}), flush=True)
    finally:
        await d.stop()
        await w.stop()

asyncio.run(main(pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])))
