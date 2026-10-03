[English](../../en/04-foundations/20-authorization-provider.md) · [中文](20-authorization-provider.md)

# 授权提供方

由什么来决定谁能做什么、能对哪些记录做，它背后的两份契约，以及可以放在这两份契约后面的槽位族。读者是要加权限键、要让列表只给某些人看某些行、要加共享，或者想换掉授权实现的人。

## 范围

两种权限，以及从第二种长出来的东西：

| | 本项目叫法 | 载体 | 回答 | 业界标准叫法 |
|---|---|---|---|---|
| 功能权限 | 权限键（`erp.sales.confirm`） | RBAC：键装进角色，角色授给人 | 这个人到底能不能调这个动作？ | 功能级授权（OWASP BFLA） |
| 数据权限 | 数据范围 | RBAC 分配（每个角色、每个键上的档位与维度取值），加固定属性过滤（每个组件在自己版本里声明的列：`owner_id`、`dept_path`、`warehouse_id`、`legal_entity_id`） | 能对哪些行？ | 对象级授权（OWASP BOLA） |

在数据权限之上还有：**记录共享**（这一条记录，给这个人、角色或部门，可以带截止日期）、**关系派生的访问**（团队成员、项目成员、未关闭待办的处理人）、**委托**（A 的审批由 B 代办一周）、**字段级权限**（成本、价格列）、**限时授予**，以及**审计与解释**（"为什么我看不到"）。

不归授权、留在组件代码里的：业务不变量（"只有草稿能改价"）和职责分离（"建单人不能审批自己的单"）。token 的签发和用户目录见 [21-identity-provider.md](21-identity-provider.md)。

## 选择

**一个公式。** 对一个人 P、一个键 K、一行 r：

```
visible(P, K, r) =   rule(P, K, r)      -- 档位 × 维度：owner/org 两维之间 OR，各资源维度之间 AND
                   OR shared(P, r)      -- 对这一条记录的直接授予
                   OR derived(P, r)     -- 一跳：团队、项目、未关闭的待办
effective(P)     = P 自己全部授予的并集，再与委托链上每一环的天花板取交集
field(P, K, r)   = visible(P, K, r) AND P 持有该字段键
每一项授予都带 [valid_from, valid_until)，在读取时判定
```

一个人内部仍是纯并集、没有 Deny（[0204](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md)）；只有委托链取交集，相当于 permission boundary。两条性质是契约的一部分：授予只会让可见范围变大；以及 **List/Can 一致**：一行出现在键 K 的列表里，当且仅当对 K 的单条判定说它可见。

- **两份契约。** **provider 契约** `infra.authz.v2`，authz 槽位的每个成员都实现；**资源契约**，SDK 在每个声明了资源的组件里自动挂出。规则所需的属性留在拥有这行数据的组件里；authz 只持有显式授予和关系。
- **决策留在本地。** 键、档位、取值、字段、天花板随 bundle 下发；直接授予进组件自己 schema 里的一张投影表；列表是一条静态参数化 SQL 谓词。只有声明了的 graph 类型、或者投影落后于一致性令牌时，请求才会走到 provider。
- **槽位族**，全部在阶段 06 内建，顺序是：`infra/authz`（原生，默认）→ `infra/authz-static`（文件，无库）→ `infra/authz-openfga`（ReBAC）。Cedar 或 OPA 只在有真实 ABAC 需求时才建，而且只用于动作判定。族契约放在独立仓库 `contract-infra-authz`（检出在 `contracts/infra/authz`）：proto、REST 与事件契约、错误 reason、bundle 的含义（`EVALUATION.md`）以及锁定它的决策向量。
- **任何组件都不依赖某个成员。** 所有调用都打共享地址 `AUTHZ_URL`（REST）和 `AUTHZ_GRPC_URL`（gRPC）；`infra/iam-casdoor` 到 `infra/authz` 的依赖边删除。
- **档位**：`own`、`dept`（只本部门，不含下级）、`subtree`、`all`；若干个部门子树的自定义组合，是 `org` 维度的取值。
- **已经定了的答案**：共享一条记录可以顺带给出对这一条的查看权，但永远不顺带动作键（确认、取消、关闭要角色键；每个关系声明自己授予什么）；共享要持有该类型的 share 键，且自己至少有要授出的那一级；调用者看不见的记录，读和命令一律答 `404`，只有看得见但不允许这个动作时才答 `403`（调用方持有这个动作的键、但这条记录不在该键的范围内时是 `OUT_OF_SCOPE`，调用方没有这个键时是 `MISSING_PERMISSION`）；生产环境只读的"以他人身份查看"要 `infra.authz.impersonate` 键，日志带 `act` 链，并通知被查看的人。
- **AI 代理只留位子、不开发**：`act.kind` 允许 `agent`，bundle 能力 `agents` 默认 `false`，profile 与天花板的形状一次定好，权限键接受一个可选的 `delegable` 字段，目前没有任何东西填写或读取它。以后启用全部只增。

**状态**：已在用：`infra/authz` 2.0.x 在 `/authz/bundle` 提供 v1 bundle（角色 → 键、`stale_since`），每个组件用自己的范围代码过滤行，inventory 和 finance 各有自己的授权表。已定：本文其余全部内容，即 v2 设计，随 3.0.0 统一升级落地，`infra/authz-static` 和 `infra/authz-openfga` 在阶段 06 内建。

## 端口契约

**寻址。** `config/vars.yaml` 里的两个共享键，都是指向已安装成员的 brickKit `$endpoint:` 引用：`AUTHZ_URL: $endpoint:infra/authz`（REST 基础地址）和 `AUTHZ_GRPC_URL: $endpoint:infra/authz:grpc`（名为 `grpc` 的端口，按 `host:port` 拨号）（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）。两者都由 brickKit 按 `brickkit.yaml` 算出，所以成员发版或进外壳，这里都不用改。`AUTHZ_URL` 取代 `AUTHZ_BUNDLE_URL`，后者在 3.0.0 统一升级里删除；没有过渡期。

**身份 claims**（由 IAM 成员签发，见 [21-identity-provider.md](21-identity-provider.md)；token 里仍然一个键都不放，[0203](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md)）：`sub`、`typ`、`roles[]`、`dept_path`、`tenant_id`（`org_id` 弃用）、`act`（`{sub, kind: user|agent|svc}`，可嵌套）、`ceil[]`（天花板 profile 码）、`dg`（委托授予 id）、`azp`。

**bundle v2。** `GET {AUTHZ_URL}/authz/v2/bundle`，按 `ETag` 条件请求，每 15 秒以及每次收到 poke 时拉取：

```json
{ "contract": "authz/2.0", "revision": "18234",
  "capabilities": { "core": true, "admin_write": true, "sharing": true, "relation_sync": true, "check": true,
                    "graph": false, "list_objects": { "max_results": 1000 }, "delegation": true,
                    "agents": false, "impersonation": false, "access_review": true,
                    "explain_paths": true, "conditions": false },
  "roles":  { "dev_sales_rep": ["erp.sales.view", "erp.sales.cancel", "erp.sales.pricing.read"] },
  "grants": { "dev_sales_rep": { "levels": { "erp.sales.view": "subtree", "erp.sales.cancel": "own" } },
              "dev_east_mgr":  { "levels": { "erp.sales.view": "subtree" }, "values": { "org": ["/1/3/", "/1/7/"] } },
              "dev_wh_south":  { "values": { "warehouse": ["7"] }, "until": 1760000000 } },
  "profiles": {}, "delegations": [], "stale_since": { "u_123": 1759400000 },
  "revoked_grants": {}, "catalog_digest": "sha256:…" }
```

- 多个角色给了同一个键：取最高档；授了键却没写档位，按 `own`。取值按键求并集；`*` 表示全部，而且只能显式授予。
- `until` 在本地按时钟判定；到期不需要事件。
- `contract` 缺失或不是 `authz/2.*` 的 bundle 被拒用，并记 ERROR；没有 v1 退化。
- 不认识的字段和能力名一律忽略。

**provider 服务** `infra.authz.v2.AuthzProvider`（gRPC，系统面，见 [14-system-rpc.md](14-system-rpc.md)）：`ResolveClaims`（iam 登录和刷新时调）、`GetBundle`、`ReadChanges` 与 `ReadTuples`（变更流与快照）、`WriteTuples`（幂等键、actor、来源组件；返回 revision）、`Check` 与 `BatchCheck`（≤ 500 条）、`ListObjects`（能力 `graph`，有上限）、`Explain`、`CreateDelegation`、`RevokeDelegation`。

**元组。** `{object: {type, id}, relation, subject, expires_at}`，subject 是 `user:<sub>`、`role:<code>`、`dept:<path>`、`dept_tree:<path>` 之一。两种来源：

| | authz 主责 | 组件主责 |
|---|---|---|
| 是什么 | 共享、委托 | 业务关系：商机团队、项目成员、待办处理人对单据的临时 viewer |
| 谁写 | 属主组件的 `_shares` 端点，先在本地检查资格，再调 `WriteTuples` | 业务事务经 outbox 写，subject 为 `infra.authz.relation.sync.v1`，按（类型, id, 关系, 来源）整组替换，version 单调 |
| 什么时候接受 | 类型和关系在目录里，且写入方的 `be-caller` 是该类型的属主 | 来源是登记的属主，且 version 更新 |
| 管理员能不能改 | 能（撤销、评审） | 不能，只读 |

**变更流。** `GET {AUTHZ_URL}/authz/v2/changes?types=…&after=<revision>&limit=500` → `{changes: [{revision, op: upsert|delete, tuple}], next, watermark}`。成员无法续上的 `after`（早于它的保留期，或者根本不是它签出的 revision，比如换了成员之后）答 `410`；SDK 随即用 `ReadTuples` 重建，再从快照的 revision 接着拉。poke `infra.authz.changed.v1`（core NATS，只带 revision，丢了无妨）触发立刻拉一次。

**一致性令牌。** `revision` 是单调的 int64，以十进制字符串传输。写入返回它；属主的 `_shares` 等自己的投影追到这个 revision 才回答。请求可以带 `X-Authz-Revision: N`：投影已到 N 或更新 → 直接答；落后 → 同步拉一次，预算 300 毫秒；仍落后 → 单条读回落到 provider 的 `Check`（`at_least = N`），列表在响应头带 `X-Authz-Consistency: stale`。

**能力。** core，每个成员都要实现：claims、键、档位、维度取值、字段键、stale、revision、目录同步、`/api/me/access`、基础 explain、限时授予。可选：`admin_write`、`sharing`、`relation_sync`、`check`、`graph`、`delegation`、`agents`、`impersonation`、`access_review`、`explain_paths`、`conditions`。缺一项能力时明确降级：

| 缺的能力 | 后端 | 前端 |
|---|---|---|
| `admin_write` | 管理写接口答 `501` | 管理页只读，带横幅提示 |
| `sharing` | `_shares` 答 `501`，reason 为 `CAPABILITY_UNAVAILABLE`，`metadata.capability = sharing`（[15](15-user-api-and-errors.md)）；投影保持为空 | 隐藏共享入口 |
| `check` | 落后于令牌的单条读答"不可见 + stale"，不回落 | 提示稍后再试 |
| `graph` | graph ids 为空，响应头 `X-Authz-Degraded: graph` | 提示 |
| `delegation`、`agents`、`impersonation` | 带 `ceil` 或 `dg` 的 token 答 `401 UNSUPPORTED_DELEGATION` | 隐藏入口 |

组件在 `assembly.yaml` 写 `requires_capabilities`，成员写 `provides_capabilities`；前者不是后者的子集时，门禁 `authz-capability-scan` 在组装期失败。

**资源契约**（REST，SDK 在每个声明了 `resources` 的组件里自动挂出；`{prefix}` 是 `/{domain}/{name}`）：

| 端点 | 回答 |
|---|---|
| `POST {prefix}/_authz/check` `{checks: [{key, type, id}]}`（≤ 500） | `{results: [{visible, allowed, reason}]}`：规则、共享、关系、委托、天花板合起来的结论 |
| `GET {prefix}/_authz/explain?key=&type=&id=` | `{decision, reasons: [{kind, source, detail}], missing: [...]}`；对调用者本人只答他自己一侧的事实；持 `infra.authz.audit` 的人拿完整答案 |
| `GET {prefix}/_shares/{type}/{id}` | 这条记录的共享；看不见时答 `404` |
| `POST {prefix}/_shares/{type}/{id}` `{subject, relation, expires_at?, idempotency_key}` | `{share, revision}`；`403 SHARE_NOT_ALLOWED`；`501 CAPABILITY_UNAVAILABLE` |
| `DELETE {prefix}/_shares/{type}/{id}/{share_id}` | `{revision}` |

跨组件的父子（订单的附件、关于某张单据的待办）：经父记录的 `_authz/check` 检查一次父记录，再列子项；跨父记录列"我能看的全部附件"不支持。

**投影**（SDK 平台迁移，只在声明了 `resources` 的组件里建）：

```sql
CREATE TABLE besdk_authz_acl (
    rtype TEXT NOT NULL, rid TEXT NOT NULL, relation TEXT NOT NULL, subject TEXT NOT NULL,
    expires_at TIMESTAMPTZ, revision BIGINT NOT NULL,
    PRIMARY KEY (rtype, rid, relation, subject));
CREATE INDEX besdk_authz_acl_subject ON besdk_authz_acl (rtype, subject, relation);
CREATE TABLE besdk_authz_cursor (scope TEXT PRIMARY KEY, revision BIGINT NOT NULL, rebuilt_at TIMESTAMPTZ);
```

**主体集合与规范谓词。** SDK 每个请求现算 `S(P) = {user:<sub>} ∪ {role:<r>} ∪ {dept:<dept_path>} ∪ {dept_tree:<dept_path 的每个祖先及其自身>} ∪ S(每个 on-behalf 委托覆盖本次键的委托人)`。没有部门的人不贡献任何 `dept` 项，数组为空就什么都不命中（fail-closed）。每个列表查询都带同一条谓词，参数全部来自 SDK：

```sql
AND (
      ( @s_all OR o.owner_id = ANY(@s_owners) OR o.dept_path = ANY(@s_dept_exact)
        OR o.dept_path LIKE ANY(@s_dept_prefix) )
        -- 有资源维度的组件再 AND：(@s_wh_all OR o.warehouse_id = ANY(@s_wh_ids))
   OR ( @s_acl AND EXISTS (SELECT 1 FROM besdk_authz_acl a
          WHERE a.rtype = 'erp.sales.order' AND a.rid = o.id::text
            AND a.relation = ANY(@s_relations) AND a.subject = ANY(@s_subjects)
            AND (a.expires_at IS NULL OR a.expires_at > now())) )
   OR o.id::text = ANY(@s_graph_ids)        -- 只给 graph 类型；其余恒为空数组
)
```

SDK 也把三个分支分开给出，慢查询可以改写成按同一个游标合并的 `UNION ALL`，语义不变。组件怎么写这段，见 [02-backend.md](../01-conventions/02-backend.md#数据范围)。

**声明**，在 `assembly.yaml` 里与 `data_scopes` 并列：`permissions` 的条目增加 `type: page|action|field` 和可选、目前不用的 `delegable`；新增 `resources` 段，写明每个类型（`<domain>.<name>.<aggregate>`，唯一属主，登记在只增的 `registry/resource-types.tsv`）、它的表、它的 `view_key`（决定这个类型的记录到底看不看得见的键，列表和单条读取都用它；必填）、它的键、关系（`viewer: {grants: [...]}`、`editor: {includes: [viewer], grants: [...]}`，组件主责的关系标 `owned_by: component`）、共享规则（键、关系、主体种类）、字段集（列、读键、写键）、一跳的 `inherits`，以及 `derivation: direct|graph`。be-ops 校验这些声明，并为每种语言生成键和类型的常量；生成物过期时门禁 `authzgen-fresh` 失败。

**字段级权限。** 字段键是 `type: field` 的权限键。属主组件把被掩码的字段置为 `null` 并列进 `_masked`；写被掩码的字段答 `403 FIELD_FORBIDDEN`；按被掩码的字段排序、过滤、聚合一律拒绝。事件是系统面，绝不未经掩码就展示给人。

**authz 发布的事件**（outbox，只增）：`infra.authz.tuple.changed.v1`、`infra.authz.scope_grant.changed.v1`、`infra.authz.delegation.changed.v1`、`infra.authz.role.changed.v1`、`infra.authz.user_role.changed.v1`（都带 actor 及其 `act` 链），以及 poke `infra.authz.changed.v1`。

**管理与自助 REST**（经网关；管理页只按族契约生成）：角色、带档位的键、维度取值；profile；`/api/me/delegations`、`/api/admin/delegations`；`/api/me/shares?direction=by_me|with_me`、`/api/admin/shares`；`/api/admin/keys/{key}/holders`、`/api/admin/access-review?type=&id=`；以及 `GET /api/me/access`，一次给全：`sub`、`act`、部门、已装组件、能力、带档位的键、取值、字段、天花板、委托给我的、revision。它替代原来分开的特性和权限两次请求。

**状态码。** bundle 标记 token 过期时答 `401 TOKEN_STALE`（随后静默刷新）；第一份 bundle 到达之前答 `503 AUTHZ_NOT_READY`（`/healthz` 保持绿）；看不见答 `404 NOT_FOUND`，由类型的 `view_key` 判定；看得见但不允许答 `403`：调用方持有路由键、但这条记录不在该键的范围内时是 `OUT_OF_SCOPE`，调用方没有这个键时是 `MISSING_PERMISSION`（[15](15-user-api-and-errors.md#访问相关的状态码)）。

**错误 domain。** 成员以自己名义抛出的 reason 一律用族的 ID，`domain: infra/authz`，不管装的是哪个成员，并列在族契约的 `errors.yaml` 里；这是"`domain` 就是组件 ID"这条规则的槽位族例外（[15](15-user-api-and-errors.md#错误体)），这样前端每个族只维护一张表。

## 备选方案

| 模型 | 例子 | 长处 | 对本项目的短处 |
|---|---|---|---|
| RBAC + 档位 + 维度取值 | 若依数据权限、Dynamics privilege depth、ERPNext User Permissions、SAP 组织级字段 | ERP 用户熟悉；每个列表一条 SQL 谓词 | 自身没有共享和关系 |
| ReBAC（Zanzibar 系） | OpenFGA、SpiceDB | 共享、嵌套、图深度；标准的一致性令牌 | 每一行的属主和部门都得写成元组；每个列表一次 `ListObjects` 是最贵的调用 |
| 策略语言 | Cedar、OPA | 条件表达力强（金额、时间、IP） | 条件参与可见性就要把策略部分求值翻成 SQL，两者都不成熟 |
| 静态文件 | 一份策略 YAML | 无库，跑起来最简单 | 没有共享，没有管理界面 |
| 数据库行级安全 | PostgreSQL RLS | 在应用之下强制 | 池化和共享连接上的会话设置、并入外壳、无法解释（[0206](../02-decisions/02-permissions/0206-no-row-level-security.md)） |
| 各组件自建授权表 | 今天的 inventory、finance | 本地、简单 | 散落各处，回答不了"这个人能看到什么"，没有审计 |

## 为什么选它

- 三条性质同时成立：热路径从不跨网络（[0202](../02-decisions/02-permissions/0202-local-permission-bundle.md)），每个组件仍能单独运行，外壳仍然只合并进程。
- 属性留在行的属主那里，显式授予留在 authz，所以没有任何业务写入需要同步调 authz，也没有任何东西要写两遍。
- 只物化直接元组；主体一侧（角色、部门祖先、委托人）在每个请求现展开。把一个人调到别的部门，变的是一张 token，投影一行都不动，没有重算风暴。
- 任何模型都能放在这两份契约后面，缺一项能力是一个看得见、测得到的行为。它覆盖了若依、ERPNext、Odoo、Salesforce、Dynamics 在 ERP 访问控制上提供的东西，另外还有委托和字段级权限。

## 为什么不选其他

- **每个列表都调 `ListObjects`**：每个列表一次网络往返；大团队里的人 id 集合能到几万；游标分页得拿全集；authz 一宕机列表就失败。
- **把每一行的属性写成元组**：每张业务单据要写两三条元组，有双写一致性问题，authz 进入每一次写入的同步路径。
- **策略条件参与可见性**：List/Can 一致就得把策略翻成 SQL；条件只允许用于动作。
- **行级安全、各组件授权表、Deny 规则**：已被 [0206](../02-decisions/02-permissions/0206-no-row-level-security.md) 和 [0204](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md) 排除；inventory 和 finance 的授权表删除。

## 什么时候换

| 成员 | 适合 | 证明了什么 |
|---|---|---|
| `infra/authz`（原生，默认） | 几乎所有 ERP / CRM 客户；除 `graph` 外的全部能力，一跳派生 | 完整契约可以在一个 PostgreSQL 上实现，不新增基础服务 |
| `infra/authz-static` | 十人左右以内、演示、边缘或离线站点、测试夹具；只有 core，策略文件在 `AUTHZ_POLICY_PATH`（不叫 `_FILE`：这个后缀只留给密钥） | 不动前端和 SDK 就能替换，以及明确降级 |
| `infra/authz-openfga` | 协作重的客户：项目、文件夹、嵌套团队、跨组织共享；增加 `graph`、`list_objects`、Expand 和 ListUsers | ReBAC 可以放在同一份契约后面；一致性令牌对得上 OpenFGA 的一致性参数。OpenFGA 本身是基础设施（[0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)） |
| Cedar 或 OPA（不建） | 在动作上有真实 ABAC 规则的客户 | 策略语言可以放在契约后面，只用于动作 |

## 怎么换

1. 用 `brickkit add` / `brickkit remove` 装上新成员、卸掉旧成员；没有组件要改依赖，因为没有组件依赖成员。
2. 改掉 `config/vars.yaml` 里 `AUTHZ_URL` 和 `AUTHZ_GRPC_URL` 中的成员 ID（`$endpoint:infra/authz-static`、`$endpoint:infra/authz-static:grpc`）。
3. 跑 `make gates`：已装组件要求了新成员不提供的能力时，`authz-capability-scan` 失败。
4. 把分配（角色、档位、维度取值、共享、委托）从旧成员导出成 NDJSON，再导入新成员，格式由族契约 `contract-infra-authz` 定义；和 [21](21-identity-provider.md#怎么换) 里身份链接的导出是同一个做法。导入 `infra/authz-static` 时写的是它的策略文件。新成员答 `410` 时，各组件的投影自己用 `ReadTuples` 重建。
5. 上线前对新成员跑一致性套件。

## 一致性测试

套件 `tools/be-acceptance/conformance/authz/`（`authzconf`），三层；决策向量不放在套件里，而是从族契约仓库的 `vectors/decision/` 读，以那里为准（`contracts/infra/authz`，按标签固定）。be-protocol 只放全协议通用的向量，并按标签引用族的 `EVALUATION.md`：

| 层 | 内容 | 断言 |
|---|---|---|
| 决策向量 `vectors/decision/*.json`（族仓库） | bundle、claims、路由键、行属性、ACL 行、时间、revision → 决策、谓词参数、主体集合、字段掩码、原因 | 每个官方 SDK 算出相同结果：取最高档、按键求值、主体展开、没有部门时数组为空、委托合并、天花板交集、到期、不是 `contract: authz/2.*` 的 bundle 被拒用 |
| provider 黑盒 `provider/` | 套件自己签测试 token；被测成员用一份夹具目录初始化 | core 必过；声明了的可选能力必过；没声明的必须答 `501 CAPABILITY_UNAVAILABLE` 并带能力名；导出的 NDJSON 导入另一个成员后，判定结果相同 |
| 端到端 `e2e/` | 夹具组件 `conformance/widget`（资源类型 `conformance.widget.widget`），用真 SDK 写成，对每个成员跑；随机生成角色、档位、取值、共享、委托、到期 | List/Can 一致；带上 revision 共享后立刻可见；撤销和到期后不可见；掩码字段为 `null` 且被列出；按掩码字段排序被拒 |

输出是一张能力矩阵（成员 × 能力 × 通过 / 降级正确 / 失败）。组件测试用的进程内假 provider 也必须通过 core，夹具才不会和真实成员漂移。

## 相关决策

- [0209 授权是一个槽位族](../02-decisions/02-permissions/0209-authz-is-a-slot-family.md)：本文是它的完整分析：这个族、两份契约、能力与套件。
- [0202 权限在本地判定](../02-decisions/02-permissions/0202-local-permission-bundle.md)：判定留在本地，对照 bundle 和投影。
- [0203 token 只承载身份，`sub` 归平台所有](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md)：身份 claim，从不是权限键。
- [0204 权限是纯并集，没有 Deny](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md)：一个主体内部是纯并集；只沿委托链取交集。
- [0205 数据范围的规则随版本发布](../02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md) 和 [0207 数据范围的分配放在 authz](../02-decisions/02-permissions/0207-scope-assignments-live-in-authz.md)：规则随版本发布；分配放在 authz。
- [0206 不用行级安全；共享引擎只有一个，在 authz](../02-decisions/02-permissions/0206-no-row-level-security.md)：不用行级安全；共享引擎只有一个，由 SDK 投影。
- [0210 委托与扮演](../02-decisions/02-permissions/0210-delegation-and-impersonation.md)：委托、扮演，代理人只留位子。
- [0211 字段级权限是一个键](../02-decisions/02-permissions/0211-field-level-permissions.md)：字段级权限。
- [0212 调用者看不见的记录答 404](../02-decisions/02-permissions/0212-invisible-records-answer-404.md)：调用者看不见的记录答 404。
- [0101 组件之间禁止 import](../02-decisions/01-architecture/0101-no-imports-between-components.md)：族契约包是第三类可以跨边界的包。
- [0104 槽位族需要多种合理实现，而且没有依赖边](../02-decisions/01-architecture/0104-variants-become-slot-families.md)：`slot:authz`。
- [0107 族成员的地址是共享变量里的 `$endpoint:` 引用](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：一律经 `AUTHZ_URL` 和 `AUTHZ_GRPC_URL`，不对任何成员建边。

## 已知限制

- 投影是最终一致的：有 poke 时约 0.1 秒，没有时最多 5 秒；一致性令牌为写入者本人和带着令牌的链接补上这个空档。
- 原生成员只做一跳派生；更深的图要 `infra/authz-openfga`，而它的列表有上限（超出答 `RESOURCE_EXHAUSTED`）。
- 不支持跨父记录的列表过滤；子项一律经父记录检查。
- 导入到缺某项能力的成员（`infra/authz-static` 没有 `sharing`）时，列出每一条它装不下的行并停止；绝不静默丢弃。
- bundle 体积随角色、profile 和活跃委托的数量增长，不随人数和记录数增长。
- 代理人和服务账号只是契约里的形状。
