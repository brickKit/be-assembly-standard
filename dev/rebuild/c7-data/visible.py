"""C7 P7: what each test account's worklist holds in the cell C7-W (pending, by task type; and what it did), and the
paused tasks the seed user sees in erp/purchase and erp/payment; the seed checklist's row comes from here. Needs
BE_ACC_IAM_TEST_PASSWORD (cellenv.sh)."""
import collections
import os

import httpx

IAM, WF = "http://127.0.0.1:18200", "http://127.0.0.1:18201"
COMPS = {"erp/purchase": "http://127.0.0.1:18085", "erp/payment": "http://127.0.0.1:18228"}
pw = os.environ["BE_ACC_IAM_TEST_PASSWORD"]


def token(user):
    r = httpx.post(f"{IAM}/api/iam/dev/token", json={"username": user, "password": pw}, timeout=30)
    r.raise_for_status()
    return r.json()["access_token"]


def pages(url, h):
    out, cursor = [], ""
    while True:
        p = httpx.get(url + ("&" if "?" in url else "?") + f"limit=200&cursor={cursor}", headers=h, timeout=30)
        if p.status_code != 200:
            return None
        p = p.json()
        out += p["tasks"]
        cursor = p["next_cursor"]
        if not cursor:
            return out


for user in ["test.bob", "test.buyer.lead", "test.finance.lead", "test.buyer.cn", "test.cashier.cn", "test.nobody"]:
    h = {"Authorization": f"Bearer {token(user)}"}
    mine, done = pages(f"{WF}/api/workflow/tasks", h), pages(f"{WF}/api/workflow/tasks/done", h)
    if mine is None:
        print(f"{user}: no worklist")
        continue
    by = collections.Counter(t["task"]["task_type"] for t in mine)
    print(f"{user}: pending {len(mine)} {dict(sorted(by.items()))}; done {len(done)}")
bob = {"Authorization": f"Bearer {token('test.bob')}"}
for comp, base in COMPS.items():
    r = httpx.get(f"{base}/be/flow/tasks?state=paused", headers=bob, timeout=30)
    print(f"{comp} paused: {r.status_code} {len(r.json().get('tasks', [])) if r.status_code == 200 else r.text[:100]}")
