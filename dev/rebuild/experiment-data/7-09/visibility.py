"""Per test account, the first page (limit 200) of every list of the trading components: rows, '+' when there is more."""
import os, sys
import httpx

PW = os.environ["SEED_PASSWORD"]
IAM = "http://127.0.0.1:18200"
LISTS = [("inventory", 18086, "/api/inventory/warehouses"), ("inventory", 18086, "/api/inventory/positions"),
         ("inventory", 18086, "/api/inventory/movements"), ("credit", 18088, "/api/credit/limits"),
         ("credit", 18088, "/api/credit/policies"), ("sales", 18084, "/api/sales/price-lists"),
         ("sales", 18084, "/api/sales/quotations"), ("sales", 18084, "/api/sales/orders"),
         ("sales", 18084, "/api/sales/deliveries"), ("billing", 18089, "/api/billing/invoices")]
USERS = ["test.bob", "test.sales.cn", "test.sales.multi", "test.sales.es", "test.mdm.admin", "test.mdm.viewer", "test.rates", "test.unit.admin.cn", "test.alice", "test.revoked", "test.expired", "test.nobody"]
with httpx.Client(timeout=30) as h:
    print("account".ljust(18), " ".join(p.rsplit("/", 1)[1][:10].rjust(10) for _, _, p in LISTS))
    for u in USERS:
        r = h.post(IAM + "/api/iam/dev/token", json={"username": u, "password": PW})
        tok = r.json()["access_token"]
        cells = []
        for _, port, path in LISTS:
            r = h.get(f"http://127.0.0.1:{port}{path}?limit=200", headers={"Authorization": f"Bearer {tok}"})
            if r.status_code != 200:
                cells.append(str(r.status_code))
                continue
            body = r.json()
            rows = next(v for v in body.values() if isinstance(v, list))
            cells.append(f"{len(rows)}{'+' if body.get('next_cursor') else ''}")
        print(u.ljust(18), " ".join(c.rjust(10) for c in cells))
