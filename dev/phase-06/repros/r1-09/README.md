# R1-09 Casdoor：access token 的 `aud`，以及 discovery + PKCE 能否在浏览器端走完

> 开发文档，只给本项目自己用；正式文档不得链接本目录。对应 `sdk-redesign.md` §7.9 第 9 条，lane K2。
> 2026-10-02 实测。全部在一次性容器里做（`r1-k2-pg`、`r1-k2-casdoor`、网络 `r1-k2-net`），没碰 be-casdoor / be-postgres；做完已删除（`down.sh`）。

## 假设

| # | 假设 | 为什么要先验 |
|---|---|---|
| H1 | Casdoor 的 OIDC discovery 文档给出完整的授权端点、token 端点、JWKS，并声明 `code_challenge_methods_supported: [S256]` | 前端改成"只读 discovery、不写厂商路径"（foundations 21） |
| H2 | 公共客户端（SPA，不带 client_secret）在**浏览器里**用授权码 + PKCE 换到 token：跨源的 discovery、token 端点、JWKS 都过得了 CORS | 前端今天用的 `/api/login/oauth/access_token` 被怀疑是私有路径；要确认标准路径可用 |
| H3 | PKCE 是被强制的：错的 / 缺的 verifier 被拒；不做 PKCE 的公共客户端换不到码 | 否则 PKCE 只是摆设 |
| H4 | Casdoor 签的 access token 的 `aud` 是什么、有没有 `typ` / `jti` / `iss`、`sub` 是什么 | 决定组件能否误收 IdP 的 token，以及 iam 成员怎么验 `subject_token` |
| H5 | Casdoor 的 refresh token 长什么样，会不会被当成 id_token 换出平台 token | foundations 21 要求族内拒收 refresh 冒充 |
| H6 | Casdoor 自带的 RFC 8693 token exchange 能不能直接用 | 决定 token exchange 放在 iam 成员里还是交给 IdP |

## 环境与版本

| 项 | 值 |
|---|---|
| Casdoor 镜像 | `casbin/casdoor:latest`，按本机摘要钉死 `sha256:1c4424819af678635d55e6979088761f526fe5a58f331ba94c371c4c0c81521f`（与 `infra/docker-compose.infra.yml` 用的是同一个本地镜像）；`/api/get-version-info` 报 **v4.1.0**，commit `9603cdd` |
| PostgreSQL | `postgres:16-alpine`（一次性，库名 `casdoor`） |
| Casdoor `origin` | `http://localhost:38000`（宿主机 `127.0.0.1:38000 → 8000`） |
| SPA | `spa/serve.py` 在 `http://localhost:38001` 上挂 `spa/spa.html`（`/` 与 `/callback` 同一页） |
| 浏览器 | Playwright 缓存里的 Chromium（`~/.cache/ms-playwright/chromium-1243`），驱动用本机 npx 缓存里已有的 `playwright-core` 1.63.0；**没有安装任何东西** |
| 应用 | 组织 `r1`、应用 `r1-spa`（clientId `r1-spa-client-id`，redirect `http://localhost:38001/callback`，grantTypes `authorization_code` `refresh_token` `token-exchange`，tokenFormat `JWT`），普通用户 `alice` |

## 步骤

1. `./up.sh`：建网络、起一次性 PG 和 Casdoor（`casdoor-conf/app.conf` 是 infra 那份的副本，只改 DSN 和 `origin`）。
2. `python3 setup.py`：用 Casdoor 首次启动自带的 `admin/123` 登录，克隆内置组织 / 应用的 JSON 改出 `r1`、`r1-spa`，加用户 `alice`。
3. `python3 spa/serve.py &`，然后 `PW_CORE=… PW_CHROMIUM=… node browser.cjs`：真 Chromium 打开 SPA → 点 login（SPA 只知道 issuer 和 client_id，授权端点从 discovery 读）→ Casdoor 登录页填 alice → 回到 `/callback` → **在页面里** `fetch` discovery 给出的 token 端点（form 编码、带 `code_verifier`、不带 secret）→ 解码三个 token → `fetch` JWKS。
4. `python3 flow.py`：无浏览器的补充用例（拿码的方式和登录页一样：`POST /api/login?…&type=code`）。PKCE 正反例、CORS 预检、claims、refresh、Casdoor 自己的 token exchange、userinfo、end_session、JWKS。
5. `python3 formats.py`：把 `tokenFormat` 依次换成 `JWT` / `JWT-Empty` / `JWT-Standard`，各走一次 PKCE 比较 claims。
6. `./down.sh`：删容器（`-v` 连匿名卷）和网络。

`run.sh` 把 1–6 串起来一键重跑。

## 原始输出

全文在 `output/`：`discovery.json`、`browser.out`（含三个 token 的完整 payload）、`flow.out`、`formats.out`。摘录：

```text
# discovery（节选）
"issuer": "http://localhost:38000",
"authorization_endpoint": "http://localhost:38000/login/oauth/authorize",
"token_endpoint": "http://localhost:38000/api/login/oauth/access_token",
"jwks_uri": "http://localhost:38000/.well-known/jwks",
"end_session_endpoint": "http://localhost:38000/api/logout",
"grant_types_supported": [..., "refresh_token", "urn:ietf:params:oauth:grant-type:token-exchange"],
"code_challenge_methods_supported": ["S256"],
"id_token_signing_alg_values_supported": ["RS256","RS512","ES256","ES384","ES512"]

# browser.out（节选）
state_matches: true
discovery.token_endpoint: http://localhost:38000/api/login/oauth/access_token
token_http_status: 200
token_response_keys: ["access_token","id_token","refresh_token","token_type","expires_in","scope"]
access_token.header: {"alg":"RS256","kid":"cert-built-in","typ":"JWT"}
access_token.payload: …86 个 claim…, "tokenType":"access-token", "azp":"r1-spa-client-id",
  "iss":"http://localhost:38000", "sub":"21ff3de6-…" (= "id"), "aud":["r1-spa-client-id"], "jti":"admin/b54c3ce9-…", "nonce":"…"
refresh_token.header: {"alg":"RS256","typ":"JWT"}            ← 没有 kid
refresh_token.payload: 同一套 86 个 claim, "tokenType":"refresh-token", "aud":["r1-spa-client-id"]
nonce_matches: true
access_token_equals_id_token: true
jwks_keys: [{"kid":"cert-built-in","alg":"RS256","kty":"RSA","use":"sig"}]
RESULT: BROWSER_PKCE_OK

# flow.out（节选）
 2 pkce_wrong_verifier   -> 400 invalid_grant "verifier is invalid"
 3 pkce_missing_verifier -> 400 invalid_grant "verifier is invalid"
 4 no_pkce_no_secret     -> 401 invalid_client "client_secret is invalid … token.CodeChallenge: empty"
 5 code_reuse            -> 400 invalid_grant "authorization code has been used"
 6 cors origin=SPA        -> preflight 200, ACAO=http://localhost:38001, Allow-Credentials=true
 7 cors origin=evil       -> preflight 403；但 form 编码的 POST 是"简单请求"不预检，实际响应 ACAO=http://evil.example
 8 access_token_claims   -> typ=null, tokenType="access-token", ttl=3600, claim_count=86, has_passwordSalt=true
10 refresh_no_secret     -> 200（公共客户端不带 secret 也能刷新）
10.5 刷新后旧 access token 调 userinfo -> "Access token doesn't exist in database"（服务端作废；JWT 本身仍能离线验签）
11 casdoor token-exchange 不带 secret -> 401 invalid_client
12 casdoor token-exchange 带 secret   -> 200，aud=["r1-spa-client-id"]，sub 不变，act=null，形状同普通 token
14 end_session(id_token_hint, post_logout_redirect_uri) -> 302 http://localhost:38001?state=x

# formats.out（节选）
JWT          -> access == id_token，86 个 claim（含 passwordSalt、passwordType、totpSecret、recoveryCodes 等键）
JWT-Empty    -> access == id_token，18 个 claim
JWT-Standard -> access == id_token，18 个 claim：标准名 preferred_username、picture、email、address，仍带 tokenType
```

## 结论

| # | 假设 | 结论 |
|---|---|---|
| H1 | discovery 完整 | **成立。** 授权端点、token 端点、JWKS、end_session 全有，声明 S256。前端今天写死的 `/login/oauth/authorize` 和 `/api/login/oauth/access_token` **就是** discovery 给出的端点，不是私有路径；问题只在"写死"，改成从 discovery 读即可。注意 JWKS 路径是 `/.well-known/jwks`（不带 `.json`），只能从 discovery 读，不能猜 |
| H2 | 浏览器端 PKCE | **成立。** 真 Chromium 跨源走完：discovery、token 端点、JWKS 都过 CORS，state、nonce 都对得上 |
| H3 | PKCE 强制 | **成立。** 错的 / 缺的 verifier 400 `invalid_grant`；没带 challenge 的码，公共客户端不带 secret 换不到（401 `invalid_client`）；码只能用一次。附带发现：CORS 不是安全边界（form POST 不预检，任意 Origin 都被回显），安全全靠 PKCE |
| H4 | access token 的 `aud` | **`aud` = `[client_id]`，`azp` = client_id，`iss` = Casdoor 的 origin，`sub` = Casdoor 用户 UUID（同 `id`），有 `jti`（`admin/<uuid>`），没有标准 `typ` claim，只有私有的 `tokenType: "access-token"`；access_token 与 id_token 是同一个 JWT。** 平台组件按 P5.3（`aud` 含 `TENANT_ID`、`typ` 必须是 `access`）天然拒收它，两条各自都够 |
| H5 | refresh token | **是同一把钥匙签的 JWT，`aud` 也是 client_id，`tokenType: "refresh-token"`，头里没有 `kid`。** 今天的 iam-casdoor 用 keyfunc 验 `subject_token`，没有 `kid` 大概率被拒，但这是巧合不是规则（未单独验证）。族契约必须写明：成员拒收 IdP 标为 refresh 的 `subject_token`，并要求 `kid` |
| H6 | Casdoor 自带 RFC 8693 | **能用，但对 SPA 没用。** 只给机密客户端（要 client_secret），签出的仍是 Casdoor 形状的 token（`aud` 是 client_id，没有 `act`）。平台 token 的 exchange 必须由 iam 成员做 |

其它观察：

- 默认 `tokenFormat: JWT` 把整条用户记录塞进 token（86 个 claim，含 `passwordSalt`、`passwordType`、`totpSecret`、`recoveryCodes` 等键；本例值为空或无害，但这是暴露面）。`JWT-Standard` 只有 18 个、用标准名。
- Casdoor 刷新之后在服务端作废旧 access token。前端只需要 Casdoor 的 id_token 换一次平台 token，不该请求 `offline_access`，也不该持有 Casdoor 的 refresh token。
- discovery 的 `issuer` 来自 `app.conf` 的 `origin`，是浏览器看到的地址；容器网络里的成员拉 JWKS 要用内部地址，但 `iss` 仍按公开 issuer 比对（infra 的 app.conf 注释里那条坑，这里再次确认）。
- 镜像是 `latest`。要固定可复现，应改钉 v4.1.0（或摘要）。

## 对设计的影响

1. **foundations 21 的 Known limits 第一条可以删**："Casdoor 的标准 token 端点能否在浏览器端完成 PKCE"已验证可以。前端（06c）改成：只配 `issuer` + `client_id`（来自 `GET /api/iam/login-config`），端点全部从 discovery 读；`scope` 用 `openid profile email`，不要 `offline_access`。
2. **iam 族契约（contract-infra-iam v1.0）据此写死的规则**：
   - 成员验 `subject_token`：`iss` = IdP issuer（公开地址），`aud` 含成员信任的 client_id，`alg` 在白名单里且等于 JWKS 钥匙的 `alg`，`kid` 必填，**拒收 IdP 标为 refresh 的 token**（Casdoor：`tokenType == "refresh-token"`；标准 IdP：`typ` 不是 ID token）；id_token 与 access_token 相同的 IdP 也照此处理。
   - 平台 token 用标准 `typ` claim，与 Casdoor 的 `tokenType` 无关；平台 `sub` 来自 `identity_links`，Casdoor 的 UUID 只进 `idp_sub`。
   - RFC 8693 exchange 由成员实现，不转交 IdP（H6）。
3. **infra/iam-casdoor 3.0.0 的成员专属要求**：建应用时 `tokenFormat: JWT-Standard`（今天 `admin.go:293` 写的是 `JWT`）；`grantTypes` 只要 `authorization_code`（不要 `password`、`refresh_token`）；redirect URI 精确登记；用 `IDP_ISSUER`（公开）和内部 JWKS 地址两个配置。
4. **infra/docker-compose.infra.yml** 的 `casbin/casdoor:latest` 建议改钉 `v4.1.0`（或摘要），由控制者决定。
