# Casdoor 4.1.0 的登出（C12 P2c，2026-11-20）

问题（设计考试 M3）：用户经身份成员登出、再去登录时，Casdoor 会不会不问密码就放行。

做法：`probe.py` 像浏览器一样直接调 Casdoor 的登录接口（应用 `be-iam`、PKCE、测试用户 `test.alice`），换取令牌，再用两种方式调结束会话地址 `/api/logout`；每步之后用 `/api/get-account` 看这个浏览器在 Casdoor 有没有会话。输出在 `out.txt`。运行：在 `tools/be-acceptance/conformance` 下、带 `cellenv.sh` 的环境 `uv run python ../../../dev/rebuild/c12-data/casdoor-logout/probe.py`。

（`silent login` 那一列是用不带密码的登录接口去试，Casdoor 4.1.0 一律答“未知的认证方式”，不能说明什么；判断用的是 `get-account`。）

| 看到的 | 结论 |
| --- | --- |
| 授权码登录之后 `get-account` 就是“请先登录” | `be-iam` 应用的“登录会话”（`enableSigninSession`）关着，Casdoor 不留会话；登出后没有能静默再登录的东西 |
| 令牌回答里 `id_token` 等于 `access_token` | Casdoor 把同一个 JWT 当两样给 |
| `/api/logout?id_token_hint=…&post_logout_redirect_uri=…` 答 302，跳回并带 `state` | 要结束 Casdoor 自己的会话时可用（开着登录会话、多应用单点登录时） |
| 只带 `client_id` 的登出，在没有会话时答 200 的 JSON、不跳转 | 不能拿它做登出后的跳转 |

决定（A178，AI 定）：要求登录应用不开登录会话与自动登录（身份成员的 `BRICKKIT.md` 部署前准备、`dev_setup.py` 显式关掉）；开着登录会话的部署要把浏览器导到 Casdoor 的结束会话地址，身份成员现在不做，记在台账的不采用里。
