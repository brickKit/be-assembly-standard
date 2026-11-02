#!/usr/bin/env python3
"""在一次性 Casdoor 里建组织 r1、公共客户端应用 r1-spa（只给 PKCE 用）和普通用户 alice。

以内置管理员 admin/123（Casdoor 首次启动自带）登录拿会话，克隆内置组织 / 应用的 JSON 再改字段，
这样不用猜 Casdoor 的完整字段表。只用标准库。
"""
import json, http.cookiejar, urllib.request

BASE = "http://localhost:38000"
SPA = "http://localhost:38001"
jar = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

def call(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"content-type": "application/json"})
    with op.open(req) as r:
        out = json.loads(r.read())
    if out.get("status") != "ok":
        raise SystemExit(f"{method} {path}: {out}")
    return out

call("POST", "/api/login", {"application": "app-built-in", "organization": "built-in",
                            "username": "admin", "password": "123", "type": "login"})

org = call("GET", "/api/get-organization?id=admin/built-in")["data"]
org.update(name="r1", displayName="R1 throwaway org", createdTime="")
call("POST", "/api/add-organization", org)

app = call("GET", "/api/get-application?id=admin/app-built-in")["data"]
app.update(name="r1-spa", displayName="R1 SPA", organization="r1", createdTime="",
           clientId="r1-spa-client-id", clientSecret="r1-spa-client-secret-throwaway",
           redirectUris=[SPA + "/callback"], grantTypes=["authorization_code", "refresh_token",
           "urn:ietf:params:oauth:grant-type:token-exchange"],
           tokenFormat="JWT", enableSignUp=False, expireInHours=1, refreshExpireInHours=24)
call("POST", "/api/add-application", app)

call("POST", "/api/add-user", {"owner": "r1", "name": "alice", "type": "normal-user",
     "password": "alice-pass-1", "displayName": "Alice", "email": "alice@example.invalid",
     "signupApplication": "r1-spa"})

got = call("GET", "/api/get-application?id=admin/r1-spa")["data"]
print(json.dumps({k: got.get(k) for k in ("name", "organization", "clientId", "redirectUris",
      "grantTypes", "tokenFormat", "cert", "expireInHours")}, indent=2))
