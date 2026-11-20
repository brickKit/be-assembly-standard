"""C12 P2c: what Casdoor 4.1.0 does with a logout, so that a logout through the identity member also ends the
provider's session (design FP06, exam M3). Drives Casdoor directly as a browser would (its login API with the
be-iam application, PKCE), exchanges the code, then tries the end-session endpoint two ways. Secrets come from the
environment (cellenv.sh), never printed. Prints one line per observation."""
import base64, hashlib, os, secrets, urllib.parse
import httpx

CASDOOR = "http://localhost:8000"
CALLBACK = "http://localhost:8200/api/iam/callback"  # registered for be-iam
ORG, USER = "brickkit", "test.alice"


def login(c: httpx.Client) -> dict:
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    q = {"clientId": "be-iam-client", "responseType": "code", "redirectUri": CALLBACK, "type": "code",
         "scope": "openid profile", "state": "s1", "code_challenge_method": "S256", "code_challenge": challenge}
    r = c.post(CASDOOR + "/api/login?" + urllib.parse.urlencode(q), json={
        "application": "be-iam", "organization": ORG, "username": USER, "password": os.environ["BE_ACC_IAM_TEST_PASSWORD"],
        "type": "code"})
    code = r.json()["data"]
    r = c.post(CASDOOR + "/api/login/oauth/access_token", data={
        "grant_type": "authorization_code", "client_id": "be-iam-client", "client_secret": os.environ["BE_ACC_IAM_CLIENT_SECRET"],
        "code": code, "code_verifier": verifier, "redirect_uri": CALLBACK})
    return r.json()


def account(c: httpx.Client) -> str:
    r = c.get(CASDOOR + "/api/get-account")
    j = r.json()
    return "signed in" if j.get("status") == "ok" else "not signed in (" + str(j.get("msg"))[:60] + ")"


def silent(c: httpx.Client) -> str:
    """Does Casdoor's own session still sign the browser in without a password? Its login API with no password."""
    r = c.post(CASDOOR + "/api/login?" + urllib.parse.urlencode({"clientId": "be-iam-client", "responseType": "code",
               "redirectUri": CALLBACK, "type": "code", "scope": "openid profile", "state": "s2"}),
               json={"application": "be-iam", "organization": ORG, "type": "code", "autoSignin": True})
    j = r.json()
    return "silent login: " + ("code issued" if j.get("status") == "ok" and j.get("data") else "refused (" + str(j.get("msg"))[:60] + ")")


for way in ["id_token_hint", "client_id"]:
    with httpx.Client(timeout=15, follow_redirects=False) as c:
        t = login(c)
        print(way, "| token answer keys:", sorted(k for k in t if t[k]), "| id_token == access_token:",
              t.get("id_token") == t.get("access_token"))
        print(way, "| before:", account(c), "|", silent(c))
        for target in ["http://localhost:8200/logged-out", CALLBACK]:
            p = {"post_logout_redirect_uri": target, "state": "st"}
            p.update({"id_token_hint": t["id_token"]} if way == "id_token_hint" else {"client_id": "be-iam-client"})
            r = c.get(CASDOOR + "/api/logout?" + urllib.parse.urlencode(p))
            print(way, "| logout to", target, "->", r.status_code, r.headers.get("location") or r.text[:120])
            if r.status_code == 302:
                break
        print(way, "| after:", account(c), "|", silent(c))
