"""C6 P5: how many opportunities each test account sees in the cell C6-O, per legal entity (CN01 / ES01 / US01),
and its funnel's count; the seed checklist's row comes from here. Needs BE_ACC_IAM_TEST_PASSWORD (cellenv.sh)."""
import os

import httpx

IAM, OPP, ORG = "http://127.0.0.1:18200", "http://127.0.0.1:18102", "http://127.0.0.1:18083"
pw = os.environ["BE_ACC_IAM_TEST_PASSWORD"]


def token(user):
    r = httpx.post(f"{IAM}/api/iam/dev/token", json={"username": user, "password": pw}, timeout=30)
    r.raise_for_status()
    return r.json()["access_token"]


bob = {"Authorization": f"Bearer {token('test.bob')}"}
les = {e["code"]: e["id"] for e in httpx.get(f"{ORG}/api/org/legal-entities?limit=200", headers=bob).json()["legal_entities"]}
for user in ["test.bob", "test.unit.admin.cn", "test.sales.cn", "test.sales.multi", "test.sales.es", "test.finance.lead",
             "test.nobody"]:
    h = {"Authorization": f"Bearer {token(user)}"}
    counts = []
    for le in ["CN01", "ES01", "US01"]:
        n, cursor = 0, ""
        while True:
            r = httpx.get(f"{OPP}/api/opportunity/opportunities?limit=200&legal_entity_id={les[le]}&cursor={cursor}", headers=h)
            if r.status_code != 200:
                counts.append(str(r.status_code))
                break
            page = r.json()
            n += len(page["opportunities"])
            if not (cursor := page.get("next_cursor") or ""):
                counts.append(str(n))
                break
    f = httpx.get(f"{OPP}/api/opportunity/funnel", headers=h)
    funnel = sum(x["count"] for x in f.json()["rows"]) if f.status_code == 200 else f.status_code
    print(f"{user} | {' / '.join(counts)} | funnel {funnel}")
