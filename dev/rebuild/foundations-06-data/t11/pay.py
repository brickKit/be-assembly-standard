"""T11's payments through the Python probe py2 of the cell T6-R (PROBE overrides its host address), and the fake payment system's control. Standard library.
  pay.py pay <reference>            a payment (test.bob, the load user, holds test.probe_py2.pay)
  pay.py wait <reference> <state>   until the probe's command is in state (60 s)
  pay.py state <reference>          the probe's command, or "none"
  pay.py fake <json>                POST /control of the fake (faults, dedupe, query_down)
  pay.py taken <reference>          how many payments the fake took under the reference
Environment: IAM_URL, BE_ACC_IAM_TEST_PASSWORD."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

PROBE, FAKE = os.environ.get("PROBE", "http://localhost:18605"), "http://localhost:18990"


def call(method, url, body=None, token=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def token():
    code, out = call("POST", os.environ["IAM_URL"] + "/api/iam/dev/token",
                     {"username": "test.bob", "password": os.environ["BE_ACC_IAM_TEST_PASSWORD"]})
    assert code == 200, (code, out)
    return out["access_token"]


def state(ref):
    code, out = call("GET", f"{PROBE}/api/probe/payment/{ref}", token=token())
    return out if code == 200 else None


def main(cmd, *args):
    if cmd == "pay":
        code, out = call("POST", f"{PROBE}/api/probe/payment", {"reference": args[0],
                         "params": {"amount": "100.00", "currency": "EUR"}}, token=token())
        print(json.dumps(out))
        return 0 if code == 200 else 1
    if cmd == "wait":
        for _ in range(120):
            s = state(args[0])
            if s and s.get("state") == args[1]:
                print(json.dumps(s))
                return 0
            time.sleep(0.5)
        print("not", args[1], json.dumps(state(args[0])))
        return 1
    if cmd == "state":
        s = state(args[0])
        print(s["state"] if s else "none")
        return 0
    if cmd == "fake":
        code, out = call("POST", f"{FAKE}/control", json.loads(args[0]))
        return 0 if code == 200 else 1
    if cmd == "taken":
        _, out = call("GET", f"{FAKE}/control")
        print(sum(1 for p in out["payments"] if p["reference"] == args[0]))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
