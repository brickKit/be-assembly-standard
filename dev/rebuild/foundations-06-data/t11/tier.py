"""T11's tiering of the Python probe's archive in a real cell (foundations item 6): what the load user reads before and
after the archive moves. Run with the suite's environment (uv run --project tools/be-acceptance/conformance).

  tier.py before <cell dir> <out dir>   the probe makes two archives (one closed 400 days ago, one open, three parts
                                        each); snapshot of both -> before.json
  tier.py compare <cell dir> <out dir> <phase>
                                        the same reads again -> <phase>.json; each must equal the snapshot (the closed
                                        archive now answers from its route, the open one from online)
  tier.py checkin <cell dir> <out dir>  the in-network calls' input for be-ops recover verify-calls (kind check) of the
                                        Python members -> check-in.json
Environment: BE_ACC_IAM_TEST_PASSWORD. Prints one line per finding; exits 1 when a read differs."""
import datetime as dt
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

import yaml

PROBE_ROUTE = {"test/probe-py": "object-parquet", "test/probe-py2": "postgres"}


class Cell:
    def __init__(self, d: pathlib.Path):
        self.dir = d
        self.deploy = yaml.safe_load((d / "deploy.yaml").read_text())
        self.ports = {}
        for c in self.deploy["components"]:
            self.ports[c["id"]] = c.get("exposePort")
            for m in c.get("members") or []:
                self.ports[m["id"]] = m.get("exposePort")
        self.probe = next(p for p in PROBE_ROUTE if p in self.ports)

    def url(self, comp: str) -> str:
        return f"http://localhost:{self.ports[comp]}"


def call(method, url, body=None, token=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", "X-Requested-With": "t11",
                                          **({"Authorization": "Bearer " + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return e.code, {"raw": raw.decode(errors="replace")[:300]}


def token(c: Cell) -> str:
    code, out = call("POST", c.url("infra/iam-casdoor") + "/api/iam/dev/token",
                     {"username": "test.bob", "password": os.environ["BE_ACC_IAM_TEST_PASSWORD"]})
    assert code == 200, (code, out)
    return out["access_token"]


def reads(c: Cell, ids: dict[str, str]) -> dict:
    tok, out = token(c), {}
    for name, i in ids.items():
        code, body = call("GET", c.url(c.probe) + f"/api/probe/archive/{i}", token=tok)
        out[name] = body if code == 200 else {"status": code, "body": body}
    return out


def before(c: Cell, out: pathlib.Path) -> int:
    tok, ids = token(c), {}
    for name, days in (("closed", 400), ("open", -1)):
        code, body = call("POST", c.url(c.probe) + "/api/probe/archive",
                          {"batch": "t11", "closed_days_ago": days, "parts": 3}, token=tok)
        assert code == 200, (code, body)
        ids[name] = body["id"]
    snap = {"probe": reads(c, ids), "archive_ids": ids}
    (out / "before.json").write_text(json.dumps(snap, indent=1, sort_keys=True))
    for name, a in snap["probe"].items():
        print(f"before: {c.probe} {name} {ids[name]} where={a.get('where')} children={len(a.get('children') or [])}")
    return 1 if any(a.get("where") != "online" for a in snap["probe"].values()) else 0


def compare(c: Cell, out: pathlib.Path, phase: str) -> int:
    snap = json.loads((out / "before.json").read_text())
    now = reads(c, snap["archive_ids"])
    (out / f"{phase}.json").write_text(json.dumps(now, indent=1, sort_keys=True))
    diffs = []
    for name, a in now.items():
        b = snap["probe"][name]
        want = PROBE_ROUTE[c.probe] if name == "closed" else "online"
        if a.get("where") != want:
            diffs.append(f"{name} answers from {a.get('where')}, not {want}")
        if a.get("root") != b.get("root") or a.get("children") != b.get("children"):
            diffs.append(f"{name} rows differ")
    print(f"{phase}: {c.probe} " + ", ".join(f"{n}={a.get('where')}" for n, a in now.items()) + f"; {len(diffs)} differences")
    for d in diffs:
        print(f"{phase}: DIFF {d}")
    return 1 if diffs else 0


def checkin(c: Cell, out: pathlib.Path) -> int:
    """be-ops's SystemAddresses: each component's gRPC port from its manifest, its alias <id>-<version> (a shell's
    members answer on the shell's address)."""
    lock = yaml.safe_load((c.dir / "brickkit.yaml").read_text())
    versions = {x["id"]: x["version"] for x in lock["components"]}
    addresses = {}
    for cid, ver in versions.items():
        m = c.dir / ".brickkit" / "manifests" / cid / ver / "component.yaml"
        if not m.exists():
            continue
        dep = (yaml.safe_load(m.read_text()).get("deployment") or {})
        for p in dep.get("extraPorts") or []:
            if p.get("name") == "grpc":
                addresses[cid] = f"{(cid + '-' + ver).replace('/', '-').replace('.', '-')}:{p['port']}"
    members = ["infra/print", c.probe]
    missing = [m for m in members if m not in addresses]
    t = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")  # the calls take a recovery point; check ignores it
    (out / "check-in.json").write_text(json.dumps({"kind": "check", "recovery": "t11-not-a-recovery", "t": t,
                                                   "addresses": addresses, "members": members}))
    print(f"check-in: members {members}, addresses {[addresses.get(m) for m in members]}")
    return 1 if missing else 0


def main(cmd: str, cell: str, out: str, *rest: str) -> int:
    c, o = Cell(pathlib.Path(cell)), pathlib.Path(out)
    o.mkdir(parents=True, exist_ok=True)
    if cmd == "before":
        return before(c, o)
    if cmd == "compare":
        return compare(c, o, rest[0])
    if cmd == "checkin":
        return checkin(c, o)
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
