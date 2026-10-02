"""r1-10: wheel availability for the Python stack. Runs INSIDE throwaway python:3.x containers (see run.sh).

  python check.py native pinned|latest
      Resolve every requirement (deps included) for THIS interpreter. Wheels are preferred; any sdist that
      comes along is built with `pip wheel` - the slim/alpine images have no C compiler, so a successful
      build proves the package is pure Python. Then install the working set and run smoke.py.
  python check.py matrix
      For the compiled packages only: is there a binary wheel for cp313 / cp314 on
      glibc x86_64, glibc arm64, musl x86_64, musl arm64 (pip download --only-binary --platform, no deps)?
"""
import glob
import os
import platform
import subprocess
import sys
import tempfile

# be-sdk-python v0.5.0 pyproject (exact pins) + additions of the 3.0.0 design (sdk-redesign §5.3, apis §3)
# + infra/print, today's only Python component.
PINNED = [
    "fastapi==0.118.0", "uvicorn[standard]==0.38.0", "asyncpg==0.30.0", "nats-py==2.11.0",
    "grpcio==1.76.0", "grpcio-tools==1.76.0", "opentelemetry-api==1.38.0", "opentelemetry-sdk==1.38.0",
    "opentelemetry-exporter-otlp-proto-http==1.38.0", "prometheus-client==0.23.1", "PyYAML==6.0.3",
    "PyJWT[crypto]==2.13.0", "httpx==0.28.1", "pytest==8.4.1", "pytest-asyncio==1.2.0",
    "pyarrow", "yoyo-migrations", "aioboto3", "pypinyin", "hypothesis", "uuid6",  # 3.0.0 additions (not pinned yet)
    "weasyprint==63.1", "yoyo-migrations==9.0.0", "psycopg2-binary==2.9.10", "jinja2==3.1.6",  # infra/print
]
LATEST = list(dict.fromkeys([s.split("==")[0] for s in PINNED] + ["psycopg[binary]"]))
# compiled distributions reached by the list above (direct or transitive), with today's pin where there is one
COMPILED = {"asyncpg": "0.30.0", "grpcio": "1.76.0", "grpcio-tools": "1.76.0", "pyarrow": None, "uvloop": None,
            "httptools": None, "watchfiles": None, "websockets": None, "pydantic-core": None, "cryptography": None,
            "cffi": None, "PyYAML": "6.0.3", "psycopg2-binary": "2.9.10", "psycopg-binary": None, "aiohttp": None,
            "multidict": None, "yarl": None, "frozenlist": None, "propcache": None, "wrapt": None, "protobuf": None,
            "pillow": None, "brotli": None, "markupsafe": None}
PLATFORMS = {
    "glibc-x86_64": ["manylinux_2_28_x86_64", "manylinux_2_17_x86_64", "manylinux2014_x86_64", "manylinux1_x86_64"],
    "glibc-arm64": ["manylinux_2_28_aarch64", "manylinux_2_17_aarch64", "manylinux2014_aarch64"],
    "musl-x86_64": ["musllinux_1_2_x86_64", "musllinux_1_1_x86_64"],
    "musl-arm64": ["musllinux_1_2_aarch64", "musllinux_1_1_aarch64"],
}


def pip(*args):
    return subprocess.run([sys.executable, "-m", "pip", *args, "--disable-pip-version-check", "--no-cache-dir", "-q"],
                          capture_output=True, text=True)


def last_error(r):
    return next((l for l in reversed(r.stderr.splitlines()) if "ERROR" in l), r.stderr.strip()[-160:]).replace("ERROR: ", "")[:160]


def probe_native(spec):
    d = tempfile.mkdtemp()
    r = pip("download", "--prefer-binary", "-d", d, spec)
    if r.returncode:
        return "FAIL", last_error(r)
    files = [os.path.basename(p) for p in glob.glob(f"{d}/*")]
    sdists = [f for f in files if not f.endswith(".whl")]
    notes = []
    for s in sdists:
        b = pip("wheel", "--no-deps", "-w", tempfile.mkdtemp(), os.path.join(d, s))
        notes.append(f"sdist {s} " + ("builds without a compiler (pure Python)" if b.returncode == 0 else "NEEDS A COMPILER"))
        if b.returncode:
            return "FAIL", "; ".join(notes)
    comp = [f.removesuffix(".whl") for f in files if f.endswith(".whl") and "-none-any" not in f]
    short = [f"{w.split('-')[0]}-{w.split('-')[1]}[{w.split('-')[2]}]" for w in comp]
    return "OK", "; ".join(short + notes)


def native(mode):
    libc = platform.libc_ver()[0] or "musl"
    print(f"===== native CPython {platform.python_version()} ({platform.machine()}, {libc}), mode={mode}")
    ok = []
    for s in (PINNED if mode == "pinned" else LATEST):
        st, info = probe_native(s)
        print(f"  [{st}] {s:46s} {info}")
        ok.append(s if st == "OK" else s.split("==")[0])  # a failing pin is replaced by the latest release
    r = pip("install", "--root-user-action=ignore", "--prefer-binary", *dict.fromkeys(ok))
    print("  install working set:", "ok" if r.returncode == 0 else "FAIL " + last_error(r))
    smoke = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "smoke.py")], capture_output=True, text=True)
    print("  smoke: " + (smoke.stdout + smoke.stderr).strip().replace("\n", "\n         "))


def has_wheel(dist, ver, py, plats):
    spec = f"{dist}=={ver}" if ver else dist
    args = ["download", "--only-binary=:all:", "--no-deps", "-d", tempfile.mkdtemp(), "--python-version", py,
            "--implementation", "cp"]
    for p in plats:
        args += ["--platform", p]
    r = pip(*args, spec)
    if r.returncode:
        return "-"
    whl = glob.glob(f"{args[4]}/*.whl")
    return os.path.basename(whl[0]).split("-")[1] if whl else "?"


def matrix():
    print("===== wheel matrix (binary wheel version found, '-' = none); pinned row uses today's pin")
    cols = [(py, p) for py in ("3.13", "3.14") for p in PLATFORMS]
    print(f"  {'distribution':22s} " + " ".join(f"{py}/{p:12s}" for py, p in cols))
    for dist, pin in COMPILED.items():
        for ver in ([pin, None] if pin else [None]):
            cells = [has_wheel(dist, ver, py, PLATFORMS[p]) for py, p in cols]
            label = f"{dist}=={ver}" if ver else f"{dist} (latest)"
            print(f"  {label:22s} " + " ".join(f"{c:17s}" for c in cells))


if sys.argv[1] == "matrix":
    matrix()
else:
    native(sys.argv[2])
