#!/usr/bin/env python3
"""Can the identity member change a user's password in Casdoor with its own application's credentials, and does
Casdoor still check the old password then? (foundations item 2, T3.) Creates a throwaway user as the built-in admin,
calls /api/set-password with the login application's client_id and client_secret (a wrong old password, then the
right one), checks the new password through the development client's password grant, deletes the user. Reads the
secrets from the assembly project's .env; prints statuses and Casdoor's messages, never a secret.

    python3 -I spike.py <assembly project root>
"""
import http.cookiejar
import json
import pathlib
import sys
import urllib.parse
import urllib.request

root = pathlib.Path(sys.argv[1])
env = dict(l.split("=", 1) for l in (root / ".env").read_text().splitlines() if "=" in l and not l.startswith("#"))
BASE, ORG, USER = "http://localhost:8000", "brickkit", "spike.setpassword"
P1, P2 = "Spike-1-" + "x" * 8, "Spike-2-" + "y" * 8
admin = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
plain = urllib.request.build_opener()


def call(opener, path, body=None, form=None):
    data = json.dumps(body).encode() if body is not None else (urllib.parse.urlencode(form).encode() if form else None)
    ctype = "application/json" if body is not None else "application/x-www-form-urlencoded"
    req = urllib.request.Request(BASE + path, data=data, headers={"Content-Type": ctype})
    with opener.open(req, timeout=10) as r:
        return json.loads(r.read())


def grant(password):
    q = {"grant_type": "password", "client_id": "be-iam-dev-client", "client_secret": env["IAM_DEV_CLIENT_SECRET"],
         "username": USER, "password": password, "scope": "openid"}
    try:
        return "access_token" in call(plain, "/api/login/oauth/access_token", form=q)
    except urllib.error.HTTPError:
        return False


app = urllib.parse.urlencode({"clientId": "be-iam-client", "clientSecret": env["IAM_CASDOOR_CLIENT_SECRET"]})
out = call(admin, "/api/login", {"application": "app-built-in", "organization": "built-in", "username": "admin",
                                 "password": env["CASDOOR_ADMIN_PASSWORD"], "type": "login"})
print("admin login:", out.get("status"))
try:
    out = call(admin, "/api/add-user", {"owner": ORG, "name": USER, "createdTime": "2026-11-03T00:00:00Z",
                                        "displayName": "spike", "type": "normal-user", "password": P1,
                                        "signupApplication": "be-iam"})
    print("add-user:", out.get("status"), out.get("msg") or "")
    print("password grant with P1 before:", grant(P1))
    out = call(plain, "/api/set-password?" + app, form={"userOwner": ORG, "userName": USER, "oldPassword": "wrong",
                                                        "newPassword": P2})
    print("set-password, app credentials, wrong old password:", out.get("status"), out.get("msg") or "")
    out = call(plain, "/api/set-password?" + app, form={"userOwner": ORG, "userName": USER, "oldPassword": P1,
                                                        "newPassword": P2})
    print("set-password, app credentials, right old password:", out.get("status"), out.get("msg") or "")
    print("password grant with P1 after:", grant(P1), "| with P2 after:", grant(P2))
    out = call(plain, "/api/set-password", form={"userOwner": ORG, "userName": USER, "oldPassword": P2,
                                                 "newPassword": P1})
    print("set-password, no credentials at all:", out.get("status"), out.get("msg") or "")
finally:
    got = call(admin, f"/api/get-user?id={ORG}/{USER}").get("data")
    if got:
        out = call(admin, "/api/delete-user", got)
        print("delete-user:", out.get("status"))
