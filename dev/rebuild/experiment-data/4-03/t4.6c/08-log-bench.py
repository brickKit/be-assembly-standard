"""CPU per request and latency of serve.py under uvicorn and granian, each at fixed rates (open loop, the project's
load driver), the whole process's CPU (granian's Rust threads included) read from /proc around each window.
Usage: python bench.py <python> <seconds> <rate> [<rate> ...]"""
import json, os, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
LOAD = "<repo>/tools/be-acceptance/conformance/.bin/load"
TICK = os.sysconf("SC_CLK_TCK")


def cpu(pid):
    f = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) / TICK


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main(python, seconds, rates):
    for kind in os.environ.get("SERVERS", "uvicorn,granian").split(","):
        port = free_port()
        p = subprocess.Popen([python, os.path.join(HERE, "serve.py"), kind, str(port)], stdout=subprocess.PIPE, text=True)
        try:
            pid = int(p.stdout.readline())
            for _ in range(100):
                try:
                    socket.create_connection(("127.0.0.1", port), 0.2).close()
                    break
                except OSError:
                    time.sleep(0.1)
            url = f"http://127.0.0.1:{port}"
            subprocess.run([LOAD, "-target", url, "-op", "echo", "-bytes", "1024", "-rate", "200", "-warmup", "0s",
                            "-duration", "3s", "-out", "/dev/null"], capture_output=True)
            for rate in rates:
                out = os.path.join(HERE, f"load-{kind}-{rate}.json")
                c0 = cpu(pid)
                r = subprocess.run([LOAD, "-target", url, "-op", "echo", "-bytes", "1024", "-rate", str(rate),
                                    "-warmup", "0s", "-duration", f"{seconds}s", "-out", out], capture_output=True, text=True)
                used = cpu(pid) - c0
                d = json.load(open(out))
                ok = d.get("ok") or 0
                summary = {k: v for k, v in d.items() if not isinstance(v, list)}
                print(json.dumps({"server": kind, "rate": rate, "exit": r.returncode, "ok": ok,
                                  "cpu_ms_per_request": round(used * 1000 / max(ok, 1), 3), **summary}), flush=True)
        finally:
            p.terminate()
            p.wait(10)

main(sys.argv[1], int(sys.argv[2]), [int(x) for x in sys.argv[3:]])
