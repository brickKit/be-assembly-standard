#!/usr/bin/env python3
"""无浏览器的补充用例：PKCE 是否真的被强制、CORS 头、refresh、RFC 8693、JWT-Standard 格式。

拿授权码的方式和 Casdoor 登录页一样：POST /api/login?...&type=code（浏览器那条路见 browser.cjs）。
每一行输出是一个用例：<编号> <名字> -> <观察到的结果>。只用标准库。
"""
import base64, hashlib, http.cookiejar as cookiejar, json, os, sys, urllib.error, urllib.parse, urllib.request

BASE, SPA = "http://localhost:38000", "http://localhost:38001"
CID, REDIRECT = "r1-spa-client-id", SPA + "/callback"
DISC = json.load(urllib.request.urlopen(BASE + "/.well-known/openid-configuration"))
TOKEN = DISC["token_endpoint"]

def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def claims(jwt): p = jwt.split(".")[1]; return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
def header(jwt): p = jwt.split(".")[0]; return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))

def http(method, url, data=None, headers=None, form=True):
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode() if form else json.dumps(data).encode()
    h = {"content-type": "application/x-www-form-urlencoded" if form else "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=body, method=method, headers=h)
    try:
        with urllib.request.urlopen(req) as r: return r.status, dict(r.headers), r.read().decode()
    except urllib.error.HTTPError as e: return e.code, dict(e.headers), e.read().decode()

def get_code(challenge=None, app="r1-spa", org="r1"):
    q = {"clientId": CID, "responseType": "code", "redirectUri": REDIRECT, "scope": "openid profile email offline_access",
         "state": "s", "nonce": "n"}
    if challenge: q.update(code_challenge=challenge, code_challenge_method="S256")
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookiejar.CookieJar()))
    req = urllib.request.Request(BASE + "/api/login?" + urllib.parse.urlencode(q), method="POST",
        data=json.dumps({"application": app, "organization": org, "username": "alice", "password": "alice-pass-1",
                         "type": "code"}).encode(), headers={"content-type": "application/json"})
    out = json.loads(op.open(req).read())
    assert out["status"] == "ok", out
    return out["data"]

def pkce():
    v = b64url(os.urandom(32)); return v, b64url(hashlib.sha256(v.encode()).digest())

def exchange(code, verifier=None, secret=None):
    d = {"grant_type": "authorization_code", "client_id": CID, "code": code, "redirect_uri": REDIRECT}
    if verifier: d["code_verifier"] = verifier
    if secret: d["client_secret"] = secret
    s, _, b = http("POST", TOKEN, d)
    return s, json.loads(b)

def short(o):
    return {k: o[k] for k in ("error", "error_description") if k in o} or {k: ("<jwt>" if isinstance(v, str) and v.count(".") == 2 else v) for k, v in o.items()}

case = lambda n, name, res: print(f"{n!s:>4} {name} -> {json.dumps(res, ensure_ascii=False)}")

# 1 正向：带 challenge 拿码，带 verifier、不带 secret 换 token
v, c = pkce(); s, ok = exchange(get_code(c), verifier=v)
case(1, "pkce_ok_no_secret", {"status": s, **short(ok)})
at, it, rt = ok["access_token"], ok["id_token"], ok["refresh_token"]

# 2 错的 verifier
v2, c2 = pkce(); s, o = exchange(get_code(c2), verifier="x" * 43); case(2, "pkce_wrong_verifier", {"status": s, **short(o)})
# 3 有 challenge，换的时候不带 verifier 也不带 secret
v3, c3 = pkce(); s, o = exchange(get_code(c3)); case(3, "pkce_missing_verifier", {"status": s, **short(o)})
# 4 拿码时不带 challenge，换的时候也不带 secret（public client 不做 PKCE 能不能换到）
s, o = exchange(get_code(None)); case(4, "no_pkce_no_secret", {"status": s, **short(o)})
# 5 同一个码用两次
v5, c5 = pkce(); code5 = get_code(c5); exchange(code5, verifier=v5); s, o = exchange(code5, verifier=v5)
case(5, "code_reuse", {"status": s, **short(o)})

# 6 CORS：预检与实际响应，可信源 / 陌生源
for n, origin in ((6, SPA), (7, "http://evil.example")):
    s, h, _ = http("OPTIONS", TOKEN, headers={"Origin": origin, "Access-Control-Request-Method": "POST",
                   "Access-Control-Request-Headers": "content-type"})
    s2, h2, _ = http("POST", TOKEN, {"grant_type": "authorization_code", "client_id": CID, "code": "bogus"},
                     headers={"Origin": origin})
    pick = lambda hh: {k: v for k, v in hh.items() if k.lower().startswith("access-control-")}
    case(n, f"cors_token_endpoint origin={origin}", {"preflight": s, "preflight_headers": pick(h), "post": s2, "post_headers": pick(h2)})

# 8 claims 与头
c_at = claims(at)
case(8, "access_token_claims", {"header": header(at), "iss": c_at.get("iss"), "aud": c_at.get("aud"), "azp": c_at.get("azp"),
     "sub": c_at.get("sub"), "id": c_at.get("id"), "typ": c_at.get("typ"), "tokenType": c_at.get("tokenType"),
     "jti": c_at.get("jti"), "nonce": c_at.get("nonce"), "ttl": c_at["exp"] - c_at["iat"], "claim_count": len(c_at),
     "has_passwordSalt": "passwordSalt" in c_at, "id_token_equals_access_token": at == it})
c_rt = claims(rt)
case(9, "refresh_token_shape", {"header": header(rt), "tokenType": c_rt.get("tokenType"), "aud": c_rt.get("aud"),
     "ttl": c_rt["exp"] - c_rt["iat"]})

# 10 public client 刷新（不带 secret）
s, _, o = http("POST", TOKEN, {"grant_type": "refresh_token", "client_id": CID, "refresh_token": rt, "scope": "openid"})
o = json.loads(o); case(10, "refresh_no_secret", {"status": s, **short(o)})
# 刷新之后 Casdoor 在服务端作废了旧的 access token（JWT 本身照样能离线验签）；后面的用例用新的一对
old_at = at
at, it = o["access_token"], o["id_token"]
s, _, b = http("GET", DISC["userinfo_endpoint"], headers={"Authorization": "Bearer " + old_at})
case(10.5, "userinfo_with_pre_refresh_access_token", {"status": s, "body": json.loads(b).get("msg") or sorted(json.loads(b))})

# 11 Casdoor 自己的 RFC 8693 端点（只看它怎么回答，我们不依赖它）
s, _, o = http("POST", TOKEN, {"grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "client_id": CID,
             "subject_token": it, "subject_token_type": "urn:ietf:params:oauth:token-type:id_token"})
o = json.loads(o)
res = {"status": s, **short(o)}
if "access_token" in o and o["access_token"].count(".") == 2:
    cx = claims(o["access_token"]); res.update(aud=cx.get("aud"), sub=cx.get("sub"), act=cx.get("act"), tokenType=cx.get("tokenType"))
case(11, "casdoor_token_exchange_no_secret", res)
s, _, o = http("POST", TOKEN, {"grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "client_id": CID,
             "client_secret": "r1-spa-client-secret-throwaway",
             "subject_token": it, "subject_token_type": "urn:ietf:params:oauth:token-type:id_token"})
o = json.loads(o); res = {"status": s, **short(o)}
if "access_token" in o and o["access_token"].count(".") == 2:
    cx = claims(o["access_token"]); res.update(aud=cx.get("aud"), sub=cx.get("sub"), act=cx.get("act"), tokenType=cx.get("tokenType"))
case(12, "casdoor_token_exchange_with_secret", res)

# 13 userinfo 与 end_session
s, h, b = http("GET", DISC["userinfo_endpoint"], headers={"Authorization": "Bearer " + at, "Origin": SPA})
ub = json.loads(b); case(13, "userinfo", {"status": s, "acao": h.get("Access-Control-Allow-Origin"), "sub": ub.get("sub"), "aud": ub.get("aud"), "keys": sorted(ub.keys())[:14]})
q = urllib.parse.urlencode({"id_token_hint": it, "post_logout_redirect_uri": SPA + "/", "state": "x"})
req = urllib.request.Request(DISC["end_session_endpoint"] + "?" + q, method="GET")
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k): return None
try:
    r = urllib.request.build_opener(NoRedirect).open(req); case(14, "end_session", {"status": r.status, "body": r.read().decode()[:200]})
except urllib.error.HTTPError as e:
    case(14, "end_session", {"status": e.code, "location": e.headers.get("Location")})

# 15 JWKS：kid / alg
jw = json.load(urllib.request.urlopen(DISC["jwks_uri"]))
case(15, "jwks", [{k: key.get(k) for k in ("kid", "alg", "kty", "use")} for key in jw["keys"]])
