#!/usr/bin/env python3
"""换 r1-spa 的 tokenFormat（JWT / JWT-Empty / JWT-Standard），各走一次 PKCE，比较 access_token 与 id_token。"""
import json, sys, urllib.request, http.cookiejar as cj
sys.argv = [sys.argv[0]]
import flow  # 复用 flow.py 的帮手（导入时会把 flow 的 15 条用例先跑一遍，输出丢弃）
BASE = flow.BASE
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj.CookieJar()))
def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                                 method=method, headers={"content-type": "application/json"})
    out = json.loads(op.open(req).read()); assert out["status"] == "ok", out; return out
call("POST", "/api/login", {"application": "app-built-in", "organization": "built-in", "username": "admin", "password": "123", "type": "login"})
for fmt in ("JWT", "JWT-Empty", "JWT-Standard"):
    app = call("GET", "/api/get-application?id=admin/r1-spa")["data"]; app["tokenFormat"] = fmt
    call("POST", "/api/update-application?id=admin/r1-spa", app)
    v, c = flow.pkce(); s, o = flow.exchange(flow.get_code(c), verifier=v)
    a, i = flow.claims(o["access_token"]), flow.claims(o["id_token"])
    print(json.dumps({"tokenFormat": fmt, "status": s, "access_equals_id": o["access_token"] == o["id_token"],
        "access_claims": sorted(a), "id_claims": sorted(i) if o["access_token"] != o["id_token"] else "same",
        "access.aud": a.get("aud"), "access.tokenType": a.get("tokenType"), "access.typ": a.get("typ")}, ensure_ascii=False))
app = call("GET", "/api/get-application?id=admin/r1-spa")["data"]; app["tokenFormat"] = "JWT"
call("POST", "/api/update-application?id=admin/r1-spa", app)
