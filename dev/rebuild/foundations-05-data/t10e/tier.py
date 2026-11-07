"""T10e's tiering in a real cell (foundations item 5): what the users read before and after the archive units move.
Run with the suite's environment (uv run --project tools/be-acceptance/conformance), for its canonical digest.

  tier.py before <cell dir> <out dir>   test.alice grants the load user (test.bob) infra.audit.record.read; the probe
                                        makes two archives (one closed 400 days ago, one open); snapshot: every ended
                                        sales order by its ID, the audit records of three sources (history), the
                                        probe's archives -> before.json
  tier.py compare <cell dir> <out dir> <phase>
                                        the same reads again -> <phase>.json; every one must equal the snapshot (the
                                        probe's closed archive now answers from its route, the open one from online)
  tier.py checkin <cell dir> <out dir>  the in-network calls' input for be-ops recover verify-calls (kind check) of the
                                        members with data classes -> check-in.json
Environment: BE_ACC_IAM_TEST_PASSWORD. Prints one line per finding; exits 1 when a read differs."""
import asyncio
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

import yaml
from besdk import canon

AUDIT_SOURCES = ["mdm/org", "erp/sales", "infra/authz"]
PROBE_ROUTE = {"test/probe-go": "object-parquet", "test/probe-go2": "postgres"}


class Cell:
    def __init__(self, d: pathlib.Path):
        self.dir = d
        self.deploy = yaml.safe_load((d / "deploy.yaml").read_text())
        self.ports = {}
        for c in self.deploy["components"]:
            self.ports[c["id"]] = c.get("exposePort")
            for m in c.get("members") or []:
                self.ports[m["id"]] = m.get("exposePort")
        self.probe = next((p for p in PROBE_ROUTE if p in self.ports), None)

    def url(self, comp: str) -> str:
        return f"http://localhost:{self.ports[comp]}"


def call(method, url, body=None, token=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", "X-Requested-With": "t10e",
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


def token(c: Cell, user: str) -> tuple[str, str]:
    code, out = call("POST", c.url("infra/iam-casdoor") + "/api/iam/dev/token",
                     {"username": user, "password": os.environ["BE_ACC_IAM_TEST_PASSWORD"]})
    assert code == 200, (code, out)
    return out["access_token"], out["principal"]


def psql(q: str) -> list[str]:
    """The cells' database (be_experiment) through the base PostgreSQL container."""
    pw = next(l.split("=", 1)[1].strip().strip("\"'") for l in pathlib.Path(
        "/home/zhijie/Desktop/github/be-assembly-standard/.env").read_text().splitlines() if l.startswith("POSTGRES_PASSWORD="))
    out = subprocess.run(["docker", "exec", "-e", "PGPASSWORD=" + pw, "be-postgres", "psql", "-U", "postgres", "-d",
                          "be_experiment", "-Atc", q], check=True, capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if l]


def grant_audit_read(c: Cell) -> None:
    """test.alice grants test.bob the audit records' read (the cells' load user has the business operations only)."""
    admin, _ = token(c, "test.alice")
    _, bob = token(c, "test.bob")
    authz = c.url("infra/authz")
    code, out = call("GET", authz + "/api/authz/records?type=management_unit", token=admin)
    assert code == 200, (code, out)
    root = next(u["id"] for u in out.get("records") or [] if u["body"].get("root"))
    start = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    candidate = {"record_type": "grant", "governance_unit": root, "grantee": bob, "segments": [
        {"resource_type": "infra.audit.record", "operation": "infra.audit.record.read", "atoms": {},
         "read_fields": ["id", "received_at", "record", "source"],  # the query masks every field not granted (AU13)
         "valid": {"from": start}}]}
    body = {"change_key": "t10e-audit-read", "direction": "widen", "candidate": candidate,
            "candidate_digest": canon.digest("be.security.grant", 1, candidate)}
    code, out = call("POST", authz + "/api/authz/changes", body, token=admin)
    assert code == 200, (code, out)


def audit_records(c: Cell, tok: str, source: str) -> list[dict]:
    code, out = call("GET", c.url("infra/audit") + f"/api/audit/records?history=true&source={source}", token=tok)
    if code != 200:
        raise RuntimeError(f"audit history of {source}: {code} {out}")
    return sorted(out.get("records") or [], key=lambda r: r["id"])


def reads(c: Cell, ids: list[str], archive_ids: dict[str, str]) -> dict:
    """The ended orders by their IDs, the audit sources' records (history), the probe's archives."""
    tok, _ = token(c, "test.bob")
    orders = {}
    for i in ids:
        code, body = call("GET", c.url("erp/sales") + f"/api/sales/orders/{i}", token=tok)
        orders[i] = body if code == 200 else {"status": code, "body": body}
    audits = {s: audit_records(c, tok, s) for s in AUDIT_SOURCES}
    probe = {}
    if c.probe:
        for name, i in archive_ids.items():
            code, body = call("GET", c.url(c.probe) + f"/api/probe/archive/{i}", token=tok)
            probe[name] = body if code == 200 else {"status": code, "body": body}
    return {"orders": orders, "audit": audits, "probe": probe}


def before(c: Cell, out: pathlib.Path) -> int:
    grant_audit_read(c)
    tok, _ = token(c, "test.bob")
    for _ in range(60):  # the grant reaches the audit component's view at its next verification
        code, _ = call("GET", c.url("infra/audit") + "/api/audit/records?source=mdm/org", token=tok)
        if code == 200:
            break
        time.sleep(1)
    archive_ids = {}
    if c.probe:
        for name, days in (("closed", 400), ("open", -1)):
            code, body = call("POST", c.url(c.probe) + "/api/probe/archive",
                              {"batch": "t10e", "closed_days_ago": days, "parts": 3}, token=tok)
            assert code == 200, (code, body)
            archive_ids[name] = body["id"]
    ids = psql("SELECT id FROM erp_sales.sales_order WHERE state IN ('completed', 'cancelled') ORDER BY id")
    assert ids, "no ended order in the cell"
    snap = {**reads(c, ids, archive_ids), "archive_ids": archive_ids}
    (out / "before.json").write_text(json.dumps(snap, indent=1, sort_keys=True))
    bad = [i for i, o in snap["orders"].items() if "status" in o]
    print(f"before: {len(snap['orders'])} ended orders ({len(bad)} unreadable), audit records "
          + ", ".join(f"{s} {len(r)}" for s, r in snap["audit"].items())
          + (f", probe archives {sorted(archive_ids)} on {c.probe}" if c.probe else ""))
    for name, a in snap["probe"].items():
        print(f"before: probe {name} where={a.get('where')}")
    return 1 if bad or not all(snap["audit"].values()) else 0


def compare(c: Cell, out: pathlib.Path, phase: str) -> int:
    snap = json.loads((out / "before.json").read_text())
    now = reads(c, sorted(snap["orders"]), snap["archive_ids"])
    (out / f"{phase}.json").write_text(json.dumps(now, indent=1, sort_keys=True))
    diffs = [f"order {i}" for i in snap["orders"] if now["orders"].get(i) != snap["orders"][i]]
    for s in AUDIT_SOURCES:
        was, got = {r["id"]: r for r in snap["audit"][s]}, {r["id"]: r for r in now["audit"][s]}
        diffs += [f"audit {s} {i} missing" for i in was if i not in got]
        diffs += [f"audit {s} {i} differs" for i in was if i in got and got[i] != was[i]]
    for name, a in now["probe"].items():
        b = snap["probe"][name]
        want = PROBE_ROUTE[c.probe] if name == "closed" else "online"
        if a.get("where") != want:
            diffs.append(f"probe {name} answers from {a.get('where')}, not {want}")
        if a.get("root") != b.get("root") or a.get("children") != b.get("children"):
            diffs.append(f"probe {name} rows differ")
    print(f"{phase}: {len(snap['orders'])} orders, audit " + ", ".join(f"{s} {len(now['audit'][s])}" for s in AUDIT_SOURCES)
          + (", probe " + ", ".join(f"{n}={a.get('where')}" for n, a in now["probe"].items()) if now["probe"] else "")
          + f"; {len(diffs)} differences")
    for d in diffs[:50]:
        print(f"{phase}: DIFF {d}")
    return 1 if diffs else 0


def checkin(c: Cell, out: pathlib.Path) -> int:
    """be-ops's SystemAddresses: each component's gRPC port from its manifest, its alias <id>-<version>."""
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
    members = [m for m in ["infra/audit", "erp/sales", c.probe] if m]
    missing = [m for m in members if m not in addresses]
    t = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")  # the calls take a recovery point; check ignores it
    (out / "check-in.json").write_text(json.dumps({"kind": "check", "recovery": "t10e-not-a-recovery", "t": t,
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
