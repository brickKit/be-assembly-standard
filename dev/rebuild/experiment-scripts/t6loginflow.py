"""Foundations item 2, T6 step 4: the browser path end to end, every part real. Casdoor (be-casdoor), infra/iam-casdoor
run as a process the way a deployment runs it (migrate, then serve), Traefik v3.0.4 with the be-edge plugin, the Go
probe with its guard on trusting iam-casdoor's keys. The suite's test deployment (besdk.testing) issues the service
certificates and the authorization views; the view's security version after a password change is set by the test
deployment, standing in for the authorization member's consumption of the account status (foundations item 3).

Run from be-acceptance's conformance directory with the suite's environment (BE_ACC_*) and the assembly project's
.env (Casdoor's secrets; read, never printed):
    uv run python ../../../dev/rebuild/experiment-scripts/t6loginflow.py <out dir>
Every step writes one JSON line (what was expected, what came back) to <out>/steps.jsonl; any step that does not hold
makes the run fail (exit 1). Ports 8200 (the redirect URI registered for be-iam) and 9200 must be free."""
from __future__ import annotations

import asyncio
import hashlib
import json
import os
import pathlib
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.parse

import httpx

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parents[3]  # the assembly project
CONF = ROOT / "tools" / "be-acceptance" / "conformance"
sys.path.insert(0, str(CONF))

from besdk import testing  # noqa: E402
from harness import DATABASE, Deployment, Spec, fresh_bus, go_binary, manifest_version, need  # noqa: E402
from profile import identity  # noqa: E402

TRAEFIK = "traefik:v3.0.4@sha256:a208c74fd80a566d4ea376053bff73d31616d7af3f1465a7747b8b89ee34d97e"
IAM = "infra/iam-casdoor"
IAM_BASE = "http://localhost:8200"
CASDOOR = "http://localhost:8000"
ORG, USER = "brickkit", "test.it.loginflow"  # a throwaway user, made and deleted here
EDGE_PORT = 18480


def env_file() -> dict:
    out = {}
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k] = v
    return out


class Steps:
    def __init__(self, out: pathlib.Path):
        self.f, self.failed = (out / "steps.jsonl").open("w"), []

    def check(self, step: str, want, got, ok: bool | None = None) -> bool:
        ok = (want == got) if ok is None else ok
        self.f.write(json.dumps({"step": step, "want": want, "got": got, "ok": ok}, ensure_ascii=False, default=str) + "\n")
        self.f.flush()
        print(("ok  " if ok else "FAIL") + "  " + step + ("" if ok else f": want {want!r}, got {got!r}"))
        if not ok:
            self.failed.append(step)
        return ok


def digest(cookie: str) -> str:
    return hashlib.sha256(cookie.encode()).hexdigest()


async def casdoor_admin(c: httpx.AsyncClient, password: str) -> None:
    r = await c.post(CASDOOR + "/api/login", json={"application": "app-built-in", "organization": "built-in",
                                                    "username": "admin", "password": password, "type": "login"})
    assert r.json().get("status") == "ok", "Casdoor admin login"


async def browser_login(user: str, password: str) -> str:
    """What a browser does: the member's redirect, Casdoor's login form, the callback; the session cookie."""
    async with httpx.AsyncClient(timeout=15, follow_redirects=False) as c:
        r = await c.get(IAM_BASE + "/api/iam/login?return_to=/home")
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(r.headers["location"]).query)
        login = {"clientId": "be-iam-client", "responseType": "code", "redirectUri": q["redirect_uri"][0], "type": "code",
                 "scope": q["scope"][0], "state": q["state"][0], "code_challenge_method": "S256",
                 "code_challenge": q["code_challenge"][0]}
        r = await c.post(CASDOOR + "/api/login?" + urllib.parse.urlencode(login), json={
            "application": "be-iam", "organization": ORG, "username": user, "password": password, "type": "code"})
        code = r.json()["data"]
        r = await c.get(IAM_BASE + "/api/iam/callback?" + urllib.parse.urlencode({"code": code, "state": q["state"][0]}))
        return r.cookies["be_session"]


async def via_edge(method: str, path: str, cookie: str | None, body: dict | None = None, header: bool = True,
                   polling: bool = False) -> tuple[int, str]:
    headers = {"BE-Request": "1"} if header else {}
    if polling:
        headers["BE-Polling"] = "1"
    cookies = {"be_session": cookie} if cookie else {}
    async with httpx.AsyncClient(timeout=20, cookies=cookies) as c:
        r = await c.request(method, f"http://127.0.0.1:{EDGE_PORT}{path}", json=body, headers=headers)
    try:
        reason = r.json().get("reason", "")
    except ValueError:
        reason = ""
    return r.status_code, reason


def start_iam(binary: str, env: dict, log: pathlib.Path) -> subprocess.Popen:
    return subprocess.Popen([binary], env={**os.environ, **env}, stdout=log.open("a"), stderr=subprocess.STDOUT)


async def wait_ready(url: str, timeout: float = 30) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            async with httpx.AsyncClient(timeout=2) as c:
                if (await c.get(url)).status_code == 200:
                    return
        except httpx.HTTPError:
            pass
        await asyncio.sleep(0.2)
    raise AssertionError(f"{url} never became ready")


async def main(out: pathlib.Path) -> int:
    out.mkdir(parents=True, exist_ok=True)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="loginflow-"))  # certificates, keys, binaries: never in the output
    s, secrets_env = Steps(out), env_file()
    password, admin_pw = secrets_env["IAM_TEST_PASSWORD"], secrets_env["CASDOOR_ADMIN_PASSWORD"]
    world = await testing.World(tmp).start()
    spec = Spec("test/probe-go", "test_probe_go", "test.probe_go", 9600, go_binary(tmp / "probe-go"), manifest_version("go"))
    d = Deployment(world, await fresh_bus("jetstream", [spec.stream, "be.session.ended", "infra.iam.account_status"]), tmp)
    iam_bin = str(tmp / "iam")
    subprocess.run(["go", "build", "-o", iam_bin, "."], cwd=ROOT / "components" / "infra" / "iam-casdoor", check=True)
    iam_log, iam_proc, traefik = tmp / "iam.log", None, "be-loginflow-traefik"
    admin = httpx.AsyncClient(timeout=15)
    first_pw, second_pw = "Lf-1-" + secrets.token_hex(6), "Lf-2-" + secrets.token_hex(6)
    try:
        # the throwaway user
        await casdoor_admin(admin, admin_pw)
        r = await admin.post(CASDOOR + "/api/add-user", json={"owner": ORG, "name": USER, "createdTime": "2026-11-03T00:00:00Z",
                                                            "displayName": "login flow", "type": "normal-user",
                                                            "password": first_pw, "signupApplication": "be-iam"})
        assert r.json().get("status") == "ok", "add-user"

        # infra/iam-casdoor: its database, migrate, serve
        db = await testing.provision(need("BE_ACC_PG_ADMIN"), DATABASE, "infra_iam_casdoor", "infra_iam_casdoor_owner",
                                     "infra_iam_casdoor_rw")
        iam_env = {**db, **world.env(IAM), "COMPONENT_ID": IAM, "COMPONENT_VERSION": "3.0.16", "PORT": "8200",
                   "BUS_URL": d.bus.url, "IMPLEMENTATION_INSTANCE": "iam-loginflow-1", "STOP_DRAIN_DELAY": "100ms",
                   "OBJECT_STORE_URL": need("BE_ACC_S3_URL"), "OBJECT_STORE_BUCKET": "be-acceptance",
                   "OBJECT_STORE_PREFIX": "infra_iam_casdoor/", "OBJECT_STORE_ACCESS_KEY": need("BE_ACC_S3_ACCESS_KEY"),
                   "OBJECT_STORE_SECRET_KEY": need("BE_ACC_S3_SECRET_KEY"),
                   "IAM_TOKEN_ISSUER": IAM_BASE, "IAM_SIGNING_KEY_FILE": str(ROOT / ".secrets/infra-iam-casdoor/signing-key.pem"),
                   "IAM_CALLBACK_URL": IAM_BASE + "/api/iam/callback", "IAM_COOKIE_SECURE": "false",
                   "CASDOOR_URL": CASDOOR, "CASDOOR_PUBLIC_URL": CASDOOR, "CASDOOR_CLIENT_ID": "be-iam-client",
                   "CASDOOR_CLIENT_SECRET": secrets_env["IAM_CASDOOR_CLIENT_SECRET"], "IAM_DEV_EXCHANGE": "true",
                   "IAM_DEV_CLIENT_ID": "be-iam-dev-client", "IAM_DEV_CLIENT_SECRET": secrets_env["IAM_DEV_CLIENT_SECRET"]}
        mig = subprocess.run([iam_bin, "migrate"], env={**os.environ, **iam_env}, capture_output=True, text=True)
        assert mig.returncode == 0, "iam migrate failed (output not printed: it may carry configuration)"
        iam_proc = start_iam(iam_bin, iam_env, iam_log)
        await wait_ready(IAM_BASE + "/readyz")

        # the principal, through the development exchange, and its grants for the probe
        async with httpx.AsyncClient(timeout=15) as c:
            principal = (await c.post(IAM_BASE + "/api/iam/dev/token", json={"username": USER, "password": first_pw})).json()["principal"]
        world.grant(principal, *identity.grants(spec))

        # the probe: guarded, trusting iam-casdoor's tokens
        penv = await d.env(spec, {"PROBE_GUARD": "true", "IAM_ISSUER": IAM_BASE, "IAM_JWKS_URL": IAM_BASE + "/api/iam/jwks"})
        probe = await d.start(spec, penv)

        # the features document (be-ops) and Traefik with the plugin
        features = tmp / "features.json"
        subprocess.run(["go", "run", "./cmd/be-ops", "features", "--root", str(ROOT), "--out", str(features)],
                       cwd=ROOT / "tools" / "be-ops", check=True, capture_output=True)
        cert, key, ca = world.certs("infra/edge")
        (tmp / "traefik.yml").write_text(f"""entryPoints:
  web:
    address: "127.0.0.1:{EDGE_PORT}"
providers:
  file:
    filename: {tmp}/dynamic.yml
log:
  level: INFO
experimental:
  localPlugins:
    beedge:
      moduleName: github.com/brickKit/be-edge/v3
""")
        (tmp / "dynamic.yml").write_text(f"""http:
  routers:
    iam:
      rule: PathPrefix(`/api/iam`)
      entryPoints: [web]
      middlewares: [edge]
      service: iam
    rest:
      rule: PathPrefix(`/`)
      entryPoints: [web]
      middlewares: [edge]
      service: probe
  middlewares:
    edge:
      plugin:
        beedge:
          identityAddress: "127.0.0.1:9200"
          identityComponent: {IAM}
          deployment: "{world.deployment}"
          certFile: {cert}
          keyFile: {key}
          caFile: {ca}
          featuresFile: {features}
          pollInterval: 500ms
  services:
    iam:
      loadBalancer:
        servers:
          - url: {IAM_BASE}
    probe:
      loadBalancer:
        servers:
          - url: {probe.url}
""")
        subprocess.run(["docker", "rm", "-f", traefik], capture_output=True)
        subprocess.run(["docker", "run", "-d", "--name", traefik, "--network", "host", "-v", f"{tmp}:{tmp}:ro",
                        "-v", f"{pathlib.Path(cert).parent}:{pathlib.Path(cert).parent}:ro",
                        "-v", f"{ROOT}/tools/be-edge:/plugins-local/src/github.com/brickKit/be-edge/v3:ro",
                        TRAEFIK, f"--configFile={tmp}/traefik.yml"], check=True, capture_output=True)
        end = time.monotonic() + 60
        while time.monotonic() < end:  # without a session the guarded probe answers 401: Traefik and the routes are up
            try:
                if (await via_edge("POST", "/api/probe/echo", None, {"payload": "x"}))[0] == 401:
                    break
            except httpx.HTTPError:
                pass
            await asyncio.sleep(0.3)

        # --- the steps ---------------------------------------------------------------------------------------
        a = await browser_login(USER, first_pw)
        s.check("UI04 the session's token is not on the user surface", 501,
                (await via_edge("POST", "/api/iam/session/token", a))[0])
        s.check("CK-EDGE-01 a request with the session reaches the probe with the session's token", 200,
                (await via_edge("POST", "/api/probe/echo", a, {"payload": "x"}))[0])
        s.check("CK-EDGE-01 without a session the probe gets no token", (401, "TOKEN_INVALID"),
                await via_edge("POST", "/api/probe/echo", None, {"payload": "x"}))
        s.check("UI06 a state-changing request without BE-Request", (403, "CSRF_HEADER_REQUIRED"),
                await via_edge("POST", "/api/probe/echo", a, {"payload": "x"}, header=False))
        s.check("UI21 a top-level GET without BE-Request (a link from an e-mail)", 200,
                (await via_edge("GET", "/api/probe/seen", a, header=False))[0])
        s.check("UI25 features for a live session", 200, (await via_edge("GET", "/api/features", a))[0])
        s.check("UI25 features without a session", (401, "SESSION_ENDED"), await via_edge("GET", "/api/features", None))

        # UI05: several tabs at once on a fresh session: one exchange (the edge's single flight, the session lock)
        b = await browser_login(USER, first_pw)
        before = iam_log.read_text().count("SessionService/Exchange")
        answers = await asyncio.gather(*(via_edge("POST", "/api/probe/echo", b, {"payload": "x"}) for _ in range(6)))
        s.check("UI05 six tabs at once all answered", [200] * 6, [x[0] for x in answers])
        s.check("UI05 one exchange for them", 1, iam_log.read_text().count("SessionService/Exchange") - before)

        # UI22, UI23: the password changed through session a; b ends; a's cached token goes stale and is replaced
        c_ = await browser_login(USER, first_pw)
        await via_edge("POST", "/api/probe/echo", c_, {"payload": "x"})  # c has a cached token too
        s.check("UI22 the password change through the edge", 204,
                (await via_edge("POST", "/api/iam/password", a, {"old_password": first_pw, "new_password": second_pw}))[0])
        world.security_change(principal)  # the authorization member's part (foundations item 3), by the test deployment
        await asyncio.sleep(3.5)  # the probe's view renewal (W_high/2) and the edge's pull (500 ms)
        refused = probe.logs().count('"status":401')
        exchanges = iam_log.read_text().count("SessionService/Exchange")
        s.check("UI22 the session that changed it goes on: TOKEN_STALE replayed with a new token", 200,
                (await via_edge("POST", "/api/probe/echo", a, {"payload": "x"}))[0])
        s.check("UI22 precondition: the probe refused the cached token once and the edge exchanged once", (1, 1),
                (probe.logs().count('"status":401') - refused,
                 iam_log.read_text().count("SessionService/Exchange") - exchanges))
        s.check("UI23 another session of the account must log in again", (401, "SESSION_ENDED"),
                await via_edge("POST", "/api/probe/echo", b, {"payload": "x"}))
        s.check("UI23 and the third", (401, "SESSION_ENDED"), await via_edge("POST", "/api/probe/echo", c_, {"payload": "x"}))

        # UI19, UI29: iam-casdoor down: a cached session goes on; a session without a token gets 503 and is kept
        d_ = await browser_login(USER, second_pw)
        iam_proc.terminate()
        iam_proc.wait(30)
        s.check("UI19 with iam-casdoor down a cached session goes on", 200,
                (await via_edge("POST", "/api/probe/echo", a, {"payload": "x"}))[0])
        s.check("UI29 a session without a token while iam-casdoor is down", (503, "DEPENDENCY_UNAVAILABLE"),
                await via_edge("POST", "/api/probe/echo", d_, {"payload": "x"}))
        iam_proc = start_iam(iam_bin, iam_env, iam_log)
        await wait_ready(IAM_BASE + "/readyz")
        s.check("UI29 the session was kept: after iam-casdoor is back it works", 200,
                (await via_edge("POST", "/api/probe/echo", d_, {"payload": "x"}))[0])

        # UI07: logout through the edge, then the old cookie
        s.check("UI07 logout through the edge", 204, (await via_edge("POST", "/api/iam/logout", a))[0])
        s.check("UI07 the old cookie after logout", (401, "SESSION_ENDED"),
                await via_edge("POST", "/api/probe/echo", a, {"payload": "x"}))

        # CK-EDGE-07, CK-ID-02: no cookie, digest or token in Traefik's or iam-casdoor's logs
        tlog = subprocess.run(["docker", "logs", traefik], capture_output=True, text=True)
        logs = tlog.stdout + tlog.stderr + iam_log.read_text()
        leaked = [n for n, v in (("cookie", a), ("digest", digest(a)), ("password", second_pw)) if v in logs]
        s.check("CK-EDGE-07 no cookie, session digest or password in the logs", [], leaked)
        (out / "traefik.log").write_text(tlog.stdout + tlog.stderr)
    finally:
        subprocess.run(["docker", "rm", "-f", traefik], capture_output=True)
        if iam_proc and iam_proc.poll() is None:
            iam_proc.terminate()
            iam_proc.wait(30)
        try:
            got = (await admin.get(CASDOOR + f"/api/get-user?id={ORG}/{USER}")).json().get("data")
            if got:
                await admin.post(CASDOOR + "/api/delete-user", json=got)
        finally:
            await admin.aclose()
        await d.stop()
        await world.stop()
    (out / "iam.log").write_text(iam_log.read_text())
    print(f"{len(s.failed)} of the steps did not hold" if s.failed else "every step held")
    return 1 if s.failed else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main(pathlib.Path(sys.argv[1]).resolve())))
