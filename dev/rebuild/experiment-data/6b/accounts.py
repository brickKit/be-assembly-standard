"""What each seed account sees and may do in a running cell with the master data components (step 6b).

Reads: the number of rows on the first page of each list (limit 200; "+" when there is a next page). Writes: one request
per operation with an invalid body, so nothing is written: 404 means the operation is not granted (not visible), 400
(or 200 for a no-op) means it is. The customer-role write uses an invalid currency on a real partner and CN01.

    SEED_PASSWORD=... python3 -I accounts.py [iam base] [host prefix]
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

IAM = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:18200"
H = sys.argv[2] if len(sys.argv) > 2 else "http://localhost"
ORG, CUR, PAR, PRO = f"{H}:18083", f"{H}:18226", f"{H}:18225", f"{H}:18082"
ACCOUNTS = ["test.alice", "test.bob", "test.mdm.admin", "test.mdm.viewer", "test.rates", "test.sales.cn", "test.sales.es",
            "test.sales.multi", "test.unit.admin.cn", "test.revoked", "test.expired", "test.nobody"]


def call(method: str, url: str, token: str = "", body=None) -> tuple[int, dict]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def login(user: str) -> str:
    code, out = call("POST", IAM + "/api/iam/dev/token", body={"username": user, "password": os.environ["SEED_PASSWORD"]})
    if code != 200:
        sys.exit(f"{user}: the development exchange answered {code}")
    return out["access_token"]


def count(token: str, url: str, key: str) -> str:
    code, out = call("GET", url, token)
    if code != 200:
        return str(code)
    return f"{len(out.get(key) or [])}{'+' if out.get('next_cursor') else ''}"


def may(token: str, method: str, url: str, body) -> str:
    code, _ = call(method, url, token, body)
    return {404: "—", 400: "✓", 200: "✓"}.get(code, str(code))


def main() -> None:
    bob = login("test.bob")
    cn01 = next(e["id"] for e in call("GET", ORG + "/api/org/legal-entities?limit=200", bob)[1]["legal_entities"] if e["code"] == "CN01")
    partner = call("GET", PAR + "/api/partner/partners?limit=1", bob)[1]["partners"][0]["id"]
    reads = [("法人", ORG + "/api/org/legal-entities?limit=200", "legal_entities"), ("部门", ORG + "/api/org/units?limit=200", "units"),
             ("币种", CUR + "/api/currency/currencies?limit=200", "currencies"), ("汇率", CUR + "/api/currency/rates?limit=200", "rates"),
             ("伙伴", PAR + "/api/partner/partners?limit=200", "partners"), ("产品", PRO + "/api/product/products?limit=200", "products"),
             ("分类", PRO + "/api/product/categories?limit=200", "categories")]
    writes = [("组织维护", "POST", ORG + "/api/org/legal-entities", {}),
              ("币种维护", "PUT", CUR + "/api/currency/rate-types/x", {}),
              ("汇率维护", "PUT", CUR + "/api/currency/rates/spot/2026-01-01/EUR/CNY", {}),
              ("新建伙伴", "POST", PAR + "/api/partner/partners", {}),
              ("修改伙伴", "PATCH", PAR + f"/api/partner/partners/{partner}", {"name": ""}),
              ("客户角色", "PUT", PAR + f"/api/partner/partners/{partner}/roles/customer/{cn01}", {"default_currency": "bad!"}),
              ("产品维护", "POST", PRO + "/api/product/products", {})]
    print("| 账号 | " + " | ".join(r[0] for r in reads) + " | " + " | ".join(w[0] for w in writes) + " |")
    print("| --- |" + " --- |" * (len(reads) + len(writes)))
    for user in ACCOUNTS:
        t = login(user)
        row = [count(t, url, key) for _, url, key in reads] + [may(t, m, url, b) for _, m, url, b in writes]
        print(f"| `{user}` | " + " | ".join(row) + " |")


if __name__ == "__main__":
    main()
