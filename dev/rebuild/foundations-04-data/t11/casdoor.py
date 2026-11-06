"""The T11 drill's changes made in Casdoor itself (outside the recovery group, A141): a second factor added to an
account (before T), a password changed in Casdoor (after T, as a user's own change there would be). As admin, through
Casdoor's API, as the identity member's tests do. Never prints a password.
Usage: casdoor.py mfa-email <user> | mfa-off <user> | password <user> (the new password in NEW_PASSWORD) | show <user>
env: CASDOOR_URL, CASDOOR_ADMIN_PASSWORD"""
import http.cookiejar
import json
import os
import sys
import urllib.parse
import urllib.request

ORG = "brickkit"
URL = os.environ["CASDOOR_URL"]
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def call(path, body=None, form=None):
    data = json.dumps(body).encode() if body is not None else (urllib.parse.urlencode(form).encode() if form else None)
    req = urllib.request.Request(URL + path, data=data, method="POST" if data else "GET")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    with opener.open(req, timeout=10) as r:
        out = json.loads(r.read())
    if out.get("status") == "error":
        raise SystemExit(f"{path}: {out.get('msg')}")
    return out


def main(cmd, user):
    call("/api/login", {"application": "app-built-in", "organization": "built-in", "username": "admin",
                        "password": os.environ["CASDOOR_ADMIN_PASSWORD"], "type": "login"})
    u = call(f"/api/get-user?id={ORG}/{user}")["data"]
    if cmd == "mfa-email":
        call(f"/api/update-user?id={ORG}/{user}", {**u, "email": user + "@example.test", "mfaEmailEnabled": True})
    elif cmd == "mfa-off":  # a drill starts from no second factor (an earlier run may have stopped with one)
        call(f"/api/update-user?id={ORG}/{user}", {**u, "mfaEmailEnabled": False, "mfaPhoneEnabled": False,
                                                    "preferredMfaType": "", "totpSecret": "", "recoveryCodes": []})
    elif cmd == "password":
        try:
            call("/api/set-password", form={"userOwner": ORG, "userName": user, "newPassword": os.environ["NEW_PASSWORD"]})
        except SystemExit as e:  # Casdoor refuses the password the account has: it is already set
            if "must be different" not in str(e):
                raise
    u = call(f"/api/get-user?id={ORG}/{user}")["data"]
    print(json.dumps({k: u.get(k) for k in ("name", "updatedTime", "lastChangePasswordTime", "mfaEmailEnabled",
                                             "preferredMfaType", "isForbidden")}))


if __name__ == "__main__":
    main(*sys.argv[1:3])
