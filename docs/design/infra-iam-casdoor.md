# infra-iam-casdoor · IAM 适配层 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `infra/iam-casdoor` |
| 仓库名 | `infra-iam-casdoor` |
| 端口 | HTTP `8200` / gRPC `9200` ← 抄 `registry/ports.tsv` |
| schema / role | `infra_iam_casdoor` / `infra_iam_casdoor_rw`（归档 `infra_iam_casdoor_archive`） |
| 语言 | Go |
| 框架栈 | Gin + `database/sql`+`pgx stdlib` + `sqlc` + `golang-migrate`（设计书 §12.4） |
| 合并部署时进 | 外壳三 `go-infra` |
| 装配角色 | `slot:iam`（Default；替换件 `infra-iam-keycloak` 占 8221/9221，与本组件互斥） |
| 阶段 | 第三阶段 |

> 规范源是设计书 **§6.1**（iam 的形态）与**第 14 章**（权限体系）。
> ⚠️ **两处冲突，一律以第 14 章为准**（它出自决策 115/116，晚于 §6.1）：
> ① §6.1 写"JWT 携带权限 Claims"——**错**，§14.1.5 明确"权限键一个都不进 JWT"，JWT 只带 `sub`/`roles[]`/`dept_path`/`org_id`；
> ② §6.1 写"权限定义在业务组件，分配在 iam"——**分配那半错了**，角色模型与分配归 `infra-authz`（见它的设计计划 §1），
> 本组件只是把 authz 算出来的 claims 搬进 Casdoor。已回写设计书 §6.1。

## 1. 边界

**归我：**

- **官方镜像的适配层**：Casdoor 官方镜像是**带外容器**（形态 B，不进 `brickkit.yaml`），本组件是它前面那 ~500 行 Go 代码，**只有这一层是 `slot:iam`**。
- **`/api/tenant/features`**：把 `be-ops` 灌进来的"本次装配启用了哪些组件"原样下发给前端。
- **应用 token 的签发与刷新**：拿 Casdoor 的身份 token 换我们自己的应用 token（带 `roles[]`/`dept_path`/`org_id`，claims 现问 `infra-authz`），并持有 refresh token。**这是本组件的核心职责**，理由见 §3.2。
- **Webhook 事件桥接**：Casdoor 的用户增删改事件 → 我们的 `infra.iam.user.*.v1`，走 Outbox。
- **首次部署初始化**：建组织/应用/管理员、配好 OIDC 客户端，幂等可重跑。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| 用户身份、密码、登录页、OIDC 协议流 | Casdoor 官方镜像 | 我们零代码的东西不该包成组件（决策 86）。**浏览器直接和它说话，不经过我**（§6.1） |
| 角色模型、角色-权限分配、用户-角色分配 | `infra-authz` | §14 的切分。这条让 `slot:iam` 换 Keycloak 时**角色数据一行都不用迁**——它们从来就不在 Casdoor 里 |
| 单次鉴权判定 | 各组件的 `be-sdk`（进程内 map） | §14.1.4，我不在请求热路径上 |
| JWT 验签 | 各组件的 `be-sdk`（本地验签，公钥从 `iamJwksUrl` 拉） | 决策 87、决策 16：验签是本地计算，走网络调用是错的形状 |
| 组织架构主数据 | `mdm-org`（阶段五）；阶段三是 `infra-authz` 的临时 `departments` 表 | 我只是把 `dept_path` 这个字符串搬进 token |
| 用户的通知通道偏好 | `infra-notification` | 它自己持快照（见 §4 与 `infra-notification` 设计计划）。**我不做偏好中心** |

⚠️ **`data_scopes: none`**——本组件不做行级过滤：能进管理界面的人看全部，那是功能权限的事。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `refresh_tokens` | 不分区 | — | 应用 token 的刷新凭据：`jti`/`sub`/`expires_at`/`revoked_at`/`rotated_from`。**每次刷新轮换**（§14.1.6）。按在线人数有界 |
| `signing_keys` | 不分区 | — | 当前与上一把签名密钥的**元数据**（`kid`/`alg`/`not_before`/`not_after`）。⚠️ **私钥本身不进库**，从配置注入（§3.3） |
| `webhook_deliveries` | `received_at` | 月 | Casdoor webhook 的投递去重（它会重投）。只留最近窗口，其余归档 |
| `bootstrap_state` | 不分区 | — | 首次初始化的幂等标记：哪一步做过了。单行到个位数行 |
| `event_outbox` / `event_inbox` | `created_at` | 周 | 标准两张（§3.10、§11.2.5） |

强制字段全部符合 §11.2.1。

**终态列表**：`refresh_tokens` 的 `revoked` 与 `expired`；`webhook_deliveries` 写入即终态。

⚠️ **本组件不存用户表。** 用户主数据在 Casdoor 里，我只存"我签发过什么"。想查用户属性走 §3 的 `BatchGetUsers`（回源 Casdoor），**不许在这里建一张 users 影子表**——那等于把 `slot:iam` 的可替换性又焊死一次。

⚠️ **也不存角色。** 角色在 `infra-authz`，我每次签发时现问（§3.2）。**存一份"上次拿到的角色"当缓存，就是把死循环重新引进来**——那份缓存过期时签出的 token 带着旧角色，而 `stale_since` 已经把这个人标记为需要刷新。

## 3. 契约面

**gRPC（`infra.iam.v1.IamService`）：**

⚠️ **包名是 `infra.iam`，不是 `infra.iam_casdoor`。** §5.11 要求**族内契约面完全一致**——`infra-iam-keycloak` 将来要原样实现这一份契约，调用方不该因为换了实现就改 import 路径。事件名同理（§4）。

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `BatchGetUsers` | 读 | — | §3.8 强制的 `batchGet`：`sub[]` → `display_name`/`email`/`phone`/`im_accounts`。**回源 Casdoor，不落本地表** |
| `GetTenantFeatures` | 读 | — | gRPC 版的 features 清单，给 BFF 用 |

**对外 REST 路径前缀：** `/infra/iam/**`（同样是**族级**前缀，不带 casdoor）

| 路径 | 权限键 | 说明 |
|---|---|---|
| `POST /api/iam/token` | `besdk.Public` | ⭐ **换应用 token**：入参是 Casdoor 的身份 token，出参是应用 token + refresh token（§3.2 第 ② 步）。Public 是必然的——这一步的目的就是把"还没有应用身份"变成"有" |
| `POST /api/iam/token/refresh` | `besdk.Public` | ⭐ 刷新。**重新调 `ResolveClaims`**，所以角色天然最新；refresh token 轮换 |
| `POST /api/iam/logout` | 仅需登录 | 作废当前 refresh token |
| `GET /.well-known/jwks.json` | `besdk.Public` | 应用 token 的公钥。**各组件的 `iamJwksUrl` 指向这里**（不是指向 Casdoor） |
| `GET /api/tenant/features` | `besdk.Public` | 前端启动时拉。**Public 是刻意的**：还没登录就要用它决定渲染什么 |
| `POST /api/iam/webhooks/casdoor` | `besdk.Public` + 签名校验 | Casdoor 回调。**Public 指的是"不走权限键"，不是"不校验"**——用 Casdoor 的 webhook 签名验，这条必须在 `AGENTS.md` 里写死 |

⚠️ **账密校验、MFA、扫码、社交登录一条都不在这张表里**——那些是浏览器 ↔ Casdoor 的标准 OIDC 流，本组件既不代理也不转发（§6.1）。我只在**认证成功之后**接手。

### 3.1 `/api/tenant/features` 的数据从哪来

平台不给任何组件"当前装配了什么"的视图，所以只能从外面喂（§6.1）：`be-ops` 生成 `brickkit.yaml` 时把启用清单写进本组件的 `config.enabledComponents`，我读环境变量 `ENABLED_COMPONENTS` 原样下发。

⚠️ **必须是逗号分隔字符串，不能写 YAML 数组**——数组会被平台渲染成 `[a b c]`（导读第 7 条、阶段二平台断言用例 7 已经真机验过）。⚠️ 平台**不校验值**，喂错内容不会有任何运行时失败，只会让前端少几个菜单，所以**校验是 `be-ops` 自己的责任**。

### 3.2 ⭐ 两种 token：Casdoor 只证明"你是谁"，应用 token 由我签

**这是本组件唯一有设计难度的地方，也是全书最容易设计错的一处。** 先把两个约束摆出来：

| 约束 | 出处 | 说的是 |
|---|---|---|
| 认证流不经过适配层 | §6.1 | 账密/MFA/扫码这些**认证**动作，浏览器直连 Casdoor 走标准 OIDC |
| JWT 必须带 `roles[]`/`dept_path`/`org_id` | §14.1.5 | 而这些数据在 `infra-authz` 的表里，Casdoor 完全不知道 |

**分成两个 token，两条约束就都成立了：**

```
① 浏览器 ↔ Casdoor          纯 OIDC。认证 100% 归它，我不在中间（§6.1 满足）
     ↓ 身份 token（只有 sub 等身份字段，没有角色）
② 前端 → 本组件 换一次      我验 Casdoor 的签名 → 调 authz 的 ResolveClaims
     ↓                       → 用我自己的密钥签出**应用 token**（带 roles[]/dept_path/org_id）
③ 业务组件                   验的是**我的** JWKS（各组件的 iamJwksUrl 指向我，不是指向 Casdoor）
④ 刷新也走我                 刷新时重新调一次 ResolveClaims，角色天然是最新的
```

**"登录完就不该再管 Casdoor 了"——这条形态就是这个意思**：第 ① 步之后 Casdoor 完全退出，业务请求路径上没有它，刷新路径上也没有它。

⚠️ **这解释了 `infra-authz` 设计计划 §3 那句 `ResolveClaims` "登录与刷新时各调一次"**——只有本组件站在签发路径上，才存在"登录时"这个时刻。那份计划早就是按这个形态写的。

**为什么不让 Casdoor 直接签带角色的 token（把 authz 的角色镜像进 Casdoor）**——这条路看起来更省事，但有三个各自独立的致命问题，任何一个都足以否决它：

| 问题 | 说明 |
|---|---|
| **踢人链路断掉** | §14.1.6 要求"踢人 → refresh token 已撤销 → 刷新失败 → 登出"，而 `infra-authz` 设计计划 §3 把撤 refresh token 列为 **authz 自己的接口**。token 若是 Casdoor 签的，authz 撤不了它，除非反过来调 Casdoor——直接违反 authz 设计计划 §5 的"不依赖 iam，方向是反的" |
| **一个不报错的死循环** | 镜像必然是异步的：authz 改完角色写 `stale_since` → 组件 401 `token_stale` → 前端刷新 → **Casdoor 还没同步到，刷回来还是旧角色** → 再 401 → 转不出去。而服务端**每条日志都正常**（401 与刷新都是预期行为），用户侧只看到页面一直转圈 |
| **把角色数据焊回 Casdoor** | §14 把角色放进 `infra-authz`，图的就是换 Keycloak 时**角色数据一行不迁**。往 Casdoor 里镜像一份，等于把刚拆开的东西又粘回去 |

⚠️ **设计书里有两处仍按"Casdoor 直接签带 claims 的 token"写**（§6.1 的一句、附录 D 的时序图），**都是决策 115/116 把角色挪进 authz 之前的残留**，已一并回写订正。

### 3.3 签发方要承担什么（这是本组件真正的复杂度所在）

成为签发方不是白来的，四件事必须做对：

| 事项 | 怎么做 | 出错的症状 |
|---|---|---|
| 签名密钥 | 启动时从配置读私钥（`appTokenSigningKey`），**不自己生成**——合并部署时 11 个模块同进程，自己生成会让每次重启都换密钥 | 重启后所有 token 突然验不过，而日志只说"签名无效" |
| `GET /.well-known/jwks.json` | 暴露公钥。各组件的 `iamJwksUrl` 指到这里 | —— |
| 密钥轮换 | JWKS 同时挂新旧两把公钥、`kid` 区分；换私钥后旧 token 在 TTL（10 分钟）内仍可验 | 不做双挂就是一次"全员被登出" |
| refresh token 存储 | `refresh_tokens` 表，**每次刷新轮换**（§14.1.6：rotation，不滑动续期）；`infra-authz` 的踢人接口通过事件通知我作废 | —— |

⚠️ **验 Casdoor 身份 token 用的是 Casdoor 的 JWKS**（`casdoorBaseUrl` 拼出来），与我自己签应用 token 用的密钥**是两把完全不同的钥匙**，不要在实现里混用同一个 verifier。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `infra.iam.user.created.v1` | 核心 | Casdoor webhook 报告新用户 | `sub`、`display_name`、`email`、`phone`、`im_accounts`（含钉钉 unionid，若已绑定） |
| `infra.iam.user.updated.v1` | 核心 | 用户属性变更 | 同上 + `version` 单调递增 |
| `infra.iam.user.disabled.v1` | 核心 | 停用/删除 | `sub`。⚠️ **删除也发这条，不发 deleted** ——下游要的是"别再给他发消息了"，不是"把历史记录删了" |
| `infra.iam.login.v1` | 旁路 | 换到应用 token（即登录完成） | `sub`、时间、IP。仅供 `infra-audit`（阶段五）落审计 |

⚠️ **`user.*` 三条标核心不标旁路**：`infra-notification` 靠它们维护"给谁发、发到哪"的快照（见 §5），漏一条的后果是**审批通知发不出去且没有报错**——那不是分析类事件能接受的可靠性。

**消费：**

| subject | 来自 | 做什么 | 幂等与乱序怎么处理 |
|---|---|---|---|
| `infra.authz.user_role.changed.v1` | `infra-authz` | **踢人时作废该用户的 refresh token**（§14.1.6 的"刷新失败 → 登出"靠这条落地）。普通的角色增减不需要动 refresh token——下次刷新自然拿到新角色 | 幂等键 `sub + authz_revision`；重复投递是幂等的（作废已作废的行是空操作） |

⚠️ **只有"撤销/停用"这一类变更才作废 refresh token**，普通调岗不作废——否则每次人事调整都把人踢下线，而 §14.1.6 设计的路径是"401 `token_stale` → 静默刷新"，用户无感。

## 5. 依赖

**强依赖**（同步 gRPC，缺失时平台阻断启动）：

| 组件 | 调它的什么 | 为什么必须同步 |
|---|---|---|
| `infra-authz` | `ResolveClaims`：**每次签发应用 token 时调一次**（登录一次、每次刷新一次） | 签 token 那一刻必须拿到**当下**的角色，缓存就是把死循环引回来（§2 末尾）。这条边的方向与 `infra-authz` 设计计划 §5 记的完全一致（"是 iam 调我算 claims"），它的 §3 也早就写了"登录与刷新时各调一次" |

⚠️ **这条边的可用性代价要写明**：`infra-authz` 挂掉时，**已登录的人做业务不受影响**（§14.1.9 的 fail-static：组件用内存里最后一份 bundle），但**新登录与刷新会失败**。这是把 claims 做成"现问"而不是"缓存"必然付的账——换来的是角色变更零延迟、且不可能签出旧角色的 token。TTL 取 10 分钟（§14.1.6）意味着 authz 中断超过 10 分钟时，在线用户会陆续被挡在刷新这一步。

**弱依赖**（`optional: true`）：无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| **所有业务组件** | ⭐ 反过来更要紧：**没有任何组件对我建依赖边**，这是 `slot:iam` 能成立的物理前提（§5.11 硬约束）。业务组件要用户信息时走**事件快照**（`infra-notification` 就是这么做的），要验签走 `iamJwksUrl` 配置项——**都不是依赖边**。谁哪天顺手写了一条 `dependencies.components: [infra/iam-casdoor@x]`，`slot:iam` 当场失效（平台注入的变量名带实现名，换 Keycloak 时那个变量整个消失，导读第 3 条的翻版） |
| Casdoor 官方镜像 | 它是**带外容器**不是组件，地址走 `configSchema` 的 `casdoorBaseUrl`（同 §2.7.0 形态 B 的既有做法） |
| `infra-notification` | 我发事件它消费，方向是单向的；我不需要知道消息发没发出去 |

## 6. 在同步图与三枢纽里的位置

**我在同步图上只有一条出边：`infra-iam-casdoor → infra-authz`。** 这是阶段三 infra 层的第一条同步边，也是本阶段除 `crm-opportunity → mdm-*` 之外唯一的新增同步边。

**无环证明：** `infra-authz` 零出边（它的设计计划 §5：强依赖为空），所以从我出发的路径长度恒为 1。

与三枢纽（`mdm` 只读枢纽 / `erp-inventory` 物理命令枢纽 / `erp-finance` 事件汇）**完全无关**——我在业务链路之外，是一条旁路上的发牌官。与 §1.4 的"CRM 与 ERP 零同步边"也无关，我两边都不碰。

⚠️ **入边必须永远是零。** 见 §5 的"明确不依赖"第一行——这不是"目前还没有"，是这个组件作为槽位存在的前提。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `refresh_tokens` | 未过期未撤销的 | 过期/撤销满 30 天后**直接删** | 不归档（过程数据，`infra.iam.login.v1` 事件里有痕迹） |
| `signing_keys` | 当前 + 上一把 | 更早的密钥元数据满 90 天后删 | 不归档 |
| `bootstrap_state` | 永远热 | 不归档 | — |
| `webhook_deliveries` | 最近 30 天 | 超过 30 天的整月分区 | `infra_iam_casdoor_archive` |
| `event_outbox` / `event_inbox` | 已发布 30 天内 | 超过 30 天 | 清理（§11.7 全组件通则） |

⚠️ **`refresh_tokens` 永不分区**：它按"当前在线人数 × 12 小时窗口"有界（几百到几千行），而每次刷新都要按 `jti` 精确查它——分区只会让这条热路径查询跨分区找行，与 `inventory_balances` 不分区是同一个理由（§11.2.5 注）。

## 8. 参考实现

> 完整调研过程见 [`_调研记录/03-阶段三.md`](./_调研记录/03-阶段三.md) 的「infra-iam-casdoor：适配层与 claims 镜像」一节。下表是精炼版。
> ⚠️ 那份记录把每条都标了 🧭（架构推理，不依赖外部源码）或 🔍（依赖外部项目实际行为，**开工前必须核对**）——
> 本表第一行 Casdoor 那条的关键细节属于 🔍，见 §9 第 1 条。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Casdoor | 📋 开工前填 | OIDC 端点与 JWKS、身份 token 的字段构成、webhook 触发点与签名 | **本组件的对接面。** ⚠️ 改成两个 token 之后**不再需要往 Casdoor 写任何东西**，只要读得懂它签的身份 token、验得了它的签名即可——对接面比初版设计小了一大截 | Apache-2.0 | 借鉴逻辑 |
| OAuth 2.0 Token Exchange（RFC 8693） | — | `urn:ietf:params:oauth:grant-type:token-exchange` 的请求/响应形状 | §3.2 第 ② 步"拿一个 token 换另一个 token"**是有标准的**，不要自创请求格式。即使不完整实现整个 RFC，入参出参也照它的字段名 | 标准文本 | 借鉴逻辑 |
| Keycloak | 📋 开工前填 | Protocol Mapper（把用户属性映射进 token 的机制） | **对照用**：Keycloak 的 mapper 是声明式的、Casdoor 是字段固定的。族内契约要按**两边都能实现**的最小交集设计（§3 的族级包名就是这么定的） | Apache-2.0 | 借鉴实际应用 |
| Dex | 📋 开工前填 | connector 抽象 | 反面参考：它把"对接多个上游 IdP"做成了核心抽象。**我们不需要**——`slot:iam` 是装配期二选一，不是运行时多路复用 | Apache-2.0 | 借鉴逻辑 |
| Grafana | — | 它的 OIDC 集成与"角色从 token 的哪个 claim 读"的配置项 | 佐证"角色放进 token 由 IdP 签"是主流做法，不是我们的独创 | AGPL-3（**只读文档与使用体验，不看源码**） | 借鉴实际应用 |

**明确没有参考的**：Ory Hydra / Zitadel 这类"自己实现 OIDC Provider"的项目——**我们不实现 Provider，Casdoor 才是**。看它们等于在评估"要不要自己写 IdP"，那个问题决策 86/87 早就答完了（用官方镜像）。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| 大多数"IAM 中台" | 在适配层里再建一张 users 影子表，同步用户主数据 | 影子表一建，`slot:iam` 换实现就要迁数据，槽位当场失效（§2 末尾那条 ⚠️） |
| Casdoor 自带的 RBAC | 角色与权限都存 Casdoor | 那会把角色数据焊死在这个实现上。§14 刻意把角色放 `infra-authz`，就是为了换 Keycloak 时**角色数据一行不迁** |
| 常见做法：token 里塞权限键 | 直接把用户所有权限键写进 JWT | 管理员的全集顶爆 8KB header——**症状是登录成功、随后所有请求 431**（§14.1.5、决策 116） |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

**有一条，但它已经是槽位族了，不需要新增**：Casdoor vs Keycloak 正是 `slot:iam` 这个族本身（§5.11 现存三个组件级 slot 之一）。本组件是族的 Default 成员，`infra-iam-keycloak` 是替换件，端口/契约都已经在册子里留好位置。**除此之外无新分歧**——OIDC 是 RFC 标准，"多种都合理"的空间在协议层不存在。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | ~~Casdoor 的自定义 claims 写哪里~~ | ~~开工前读源码~~ | ✅ **问题不存在了**：改成两个 token 之后（§3.2），我不往 Casdoor 写任何东西，只验它签的身份 token。**这一条是被用户的一个提问推翻的**——初版设计让 Casdoor 直接签带角色的 token、由本组件镜像 claims 进去，被问了一句"登录完不是就不该管 Casdoor 了吗"才发现它同时违背了踢人链路、会造死循环、还把角色数据焊回 Casdoor（三条见 §3.2） |
| 1b | 应用 token 的签名密钥怎么给：`configSchema` 明文注入 PEM、还是挂文件？平台 Manifest **没有 volumes 字段**（§6.3），所以大概率只能走配置项 | 开工实现时 | 📋 倾向配置项注入 PEM；`brickkit.yaml` 那一格算敏感值，与 `.env` 里的数据库密码同级对待 |
| 2 | Casdoor 的 webhook 有没有投递保证与签名机制？没有的话 `webhook_deliveries` 的去重键取什么、要不要改成轮询兜底 | 同上 | 📋 |
| 3 | 钉钉 unionid 从哪来：Casdoor 的 DingTalk 第三方登录会把 unionid 存进用户属性吗？拿不到的话 `infra-notification` 就得靠人工维护映射（会牵连它的设计） | 阶段三 Task 7 实现时，与 `integration-im-dingtalk` 一起验 | 📋 |
| 4 | `infra-iam-keycloak` 什么时候建？族内契约一致要求它能原样实现 §3 那份 proto，但阶段三只建 Casdoor 一个——**契约设计得对不对，要到真建第二个成员时才验得到** | 阶段六（按客户订单排队，§9.6 档 4b） | 📋 现在的对策：§3 的契约按 Casdoor/Keycloak 两边能力的**最小交集**设计，并在 `AGENTS.md` 记一条"加 rpc 前先问 Keycloak 能不能实现" |
| 5 | 首次初始化要不要做成幂等的"每次启动都对账"，还是只跑一次？前者更安全但每次启动多几个 Casdoor API 调用 | 开工实现时 | 📋 倾向前者（`bootstrap_state` 逐步记录、每步幂等），理由同 `erp-inventory` 的 claim-first：单机测试测不出"跑了一半挂了"的中间态 |
