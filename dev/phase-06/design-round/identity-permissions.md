# 身份与权限：功能权限、数据权限、gRPC 上的用户身份、Claims 读取 API——设计审查

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准（be-sdk-* 均在 v0.5.0；组件全部 2.0.x 已发布）。
> 格式参照 `../dept-scope-analysis.md`；判据见 `README.md`（遵循 brickKit 理念、对 AI 友好、组件可替换、数据库可替换、能快速定位与迭代；可以推倒重来）。

---

## 0. 写给你：两种权限分别叫什么

| | 项目里的叫法 | 业界标准叫法 | 一句话记忆 |
|---|---|---|---|
| 第一种 | **功能权限**（functional permission），载体是**权限键**（permission key，如 `erp.sales.confirm`） | 功能级授权（function-level authorization）/ 操作权限；RBAC 里的 permission、Dynamics 里的 privilege；若依（RuoYi）叫"菜单权限 + 按钮权限"。OWASP API Top 10 里对应的漏洞叫 **BFLA**（Broken Function Level Authorization） | 管"**门**"：能不能进这个菜单、点这个按钮、调这个接口 |
| 第二种 | **数据权限**，载体是**数据范围**（data scope，`assembly.yaml` 的 `data_scopes`，维度 `org` / `owner` / `warehouse` / `legal_entity`） | 数据级 / 行级授权（row-level / object-level authorization）；若依叫"数据权限"，Odoo 叫 record rules，SAP 叫组织级授权字段。OWASP 对应 **BOLA**（Broken Object Level Authorization） | 管"**门后的柜子**"：进了门以后，同一个接口返回哪几行、能改哪几行 |

**功能权限**：决定一个人"能做哪些事"——看订单、确认订单、关账，每件事一个权限键，管理员把键装进角色、把角色授给人，改了 15 秒内生效。它只回答"能不能"，不关心是哪一张单子。

**数据权限**：决定一个人"能对哪些数据做这些事"——华东的销售只看到华东的订单、南方仓管只看到南方仓的库存。它不新增按钮，只在同一个接口里把别人的行过滤掉；条件写在各组件代码的 SQL 里。

两者的输入都是**身份**（JWT 里的 `sub`、`roles`、`dept_path`）：功能权限用 `roles`，数据权限用 `sub` 和 `dept_path`（再加上各组件自己存的仓库/法人分配）。本文的核心判断是：**两者都对，问题出在"数据权限的分配"散落在各组件、以及 gRPC 面上根本没有身份**。

---

## 1. 结论（一页）

1. **功能权限的模型是对的，不用换**：纯并集 RBAC + 本地 bundle（OPA 式本地决策点）在单机 ERP 里是最优解。要补的是 8 个缺口：审计事件声明了从没发（且没有 actor）、超级用户角色会随新键漂移、系统角色可删且没有"最后一个管理员"保护、改部门不触发 stale（最长滞后 600 秒）、**refresh token 能当 access token 用**、只发不撤的"单人授权"、两个永远检查不到的死键（`erp.inventory.reserve` / `.issue`）、前端特性端点与文档自相矛盾。都是 authz / iam / SDK 内部的小改动，不需要新决策。
2. **数据权限：规则跟版本走（0205 保留），分配集中进 authz（新决策 0207）**。今天"谁能看哪个仓库/哪个法人"已经是运行时管理数据，只是散落在 inventory、finance 各自的 `*_access` 表和管理 API 里，0205 的字面（"不许有编辑谁看哪些行的管理界面"）其实早被现状违反。推荐：authz 存**角色级的范围档位**（`own` / `subtree` / `all`，对标若依 data_scope、Dynamics 365 的 privilege depth）和**资源维度取值**（`warehouse: [3,5]`、`legal_entity: [*]`），随 bundle 下发、SDK 按"路由的权限键"求值；组件不再各建授权表。这样"这个动作只能对自己的单子做"（`cancel@own`）能表达，`.admin` 这类"用权限键扩大数据范围"的特例可以退役，一个人的全部可见范围在 authz 一处可查，前端能解释"为什么看不到"。
3. **gRPC：声明为"组件间系统协议"，用户面只走 REST**（方案 B）。今天它事实上已经是这样：Go 的 `UserClient` 在 REST 请求路径上**一个字节的 token 都不转发**（`client.go:29-33` 只读 gRPC 入站 metadata），被调方也从不验签；BFF 早就因此改走 REST 转发。要做的是把现实写成规则、让 SDK 统一行为（今天同一种情况有 Unauthenticated / Internal+ERROR / 信任请求里的 sub / 完全不检查四种结果），并修正 `02-backend.md` 里错误的说法。
4. **Claims API**：`besdk.UserFrom(ctx) (User, bool)` + `besdk.RequireUser(ctx) (User, error)`（gRPC 上返回 `codes.Unauthenticated`、REST 上映射 401）+ `besdk.ScopeFrom(ctx) (ScopeFilter, error)` + `besdk.HasPermission(ctx, key) bool`；Python / TS 同形。身份（我是谁、我的部门）和范围（我能看哪些行）分成两个对象，`ScopeOf` 保留一版作为弃用包装。测试辅助挪到 `besdktest` 子包。
5. **分两期**：一期（SDK v0.6.0 + 组件补丁版本）不需要拍板新决策，立刻能做；二期（SDK v0.7.0、authz 2.2.0、inventory/finance 2.1.0 等）先要你确认 0207。

---

## 2. 现状总览：一次请求经过哪些检查

```
浏览器 ──REST──▶ 网关 ──▶ 组件 Gin 引擎
                           └─ besdk.GET(r, path, "erp.sales.confirm", h)
                                └─ RequirePermission（authz.go:137-194）
                                     1 Public 直接放行
                                     2 本地验签 JWT（jwt.go:50-72，只认 RS256）
                                     3 iat < stale_since[sub] → 401 token_stale（bundle 里带）
                                     4 Authenticated：到此放行
                                     5 bundle 从没拉到 → 503；roles 并集里没有这个键 → 403
                                     ※ Claims 塞进 ctx（authz.go:174）
                           └─ handler → service：besdk.ScopeOf(ctx)（scope.go:74-81，取不到 panic）
                                └─ repo：静态 SQL，参数 = Prefix / Owner / 本组件查出的授权 ID 列表

组件 A ──gRPC──▶ 组件 B 的 extraPort（standalone.go:215）
                  └─ 只有 grpcRecoveryInterceptor，没有任何身份/权限检查
                  └─ ctx 里没有 Claims：调 ScopeOf 就 panic → Internal

后台：每个进程一个 bundle 轮询（bundle.go:56-85，15 秒，ETag，fail-static）
      authz /authz/bundle（http.go:53-75）= roles→keys + 有界 stale_since
```

身份的签发：Casdoor id_token → `infra/iam-casdoor` `/api/iam/token` → 用 `SystemClient` 问 authz `ResolveClaims`（`iam-casdoor/backend/internal/service/service.go:216-226`）→ 签应用 token（`tokens/tokens.go:33-38,62-80`，`sub`/`roles`/`dept_path`/`org_id`/`iat`/`exp`，TTL 600 秒）+ refresh token（同一把私钥，`typ: refresh`，TTL 7 天，`component.yaml:49-50`）。

---

## 3. 议题一：功能权限

### 3.1 现状与证据

| 环节 | 实现 | 证据 |
|---|---|---|
| 键的声明 | `assembly.yaml` 的 `permissions`；be-ops 追加进 `registry/permissions.tsv`（只增不改，46 个键） | `tools/be-ops/README.md` "permissions/data-scopes 的判据"；`registry/permissions.tsv` |
| 键进 authz | `PERMISSION_CATALOG: file://registry/permissions.tsv`，authz 每次启动 upsert | `config/infra-authz.yaml:9`；`authz/backend/internal/service/service.go:30-43` |
| 角色 | 纯并集、无 Deny；`roles` / `role_permissions` / `user_roles(expires_at)`；单人授权 = 专属角色 `u:<sub>` | `authz/migrations/001_create_authz.up.sql`；`service.go:103-116` |
| 授予 / 撤销 | `/api/admin/roles*`、`/api/admin/users/:sub/roles*`、`POST /users/:sub/permissions`、`POST /users/:sub/revoke`（踢人），全部要 `infra.authz.admin` | `authz/backend/internal/http/http.go:29-51` |
| 下发 | bundle = `roles` + `stale_since`；SDK 每 15 秒条件 GET | `repo/bundle.go:14-39`；`be-sdk-go/bundle.go:14,56-85` |
| 判定 | 路由注册强制带键；Go 编译期、Python/TS 靠 `make gates` 扫裸路由 | `be-sdk-go/authz.go:37-55`；`be-sdk-python/besdk/authz.py:169-198`；`be-sdk-ts/src/authz.ts:166-227` |
| 前端 | 可见 = `/api/tenant/features` ∩ `/api/me/permissions`；菜单手工维护（be-ops 聚合器未实现） | `frontend/standard/apps/pc/src/router/menuRegistry.ts:1-34`；`docs/en/01-conventions/03-frontend.md` Features 一节 |
| 首个管理员 | 迁移 003 建 `authz_admin`（只有 `infra.authz.admin`），启动时授给 `BOOTSTRAP_ADMIN_SUB` | `authz/migrations/003_seed_bootstrap_admin_role.up.sql:13-17`；`module/module.go:61` |
| 超级用户 | 种子脚本**直接写库**建一个角色，把**当时** `permissions.tsv` 里的全部键逐条插进去 | `authz/scripts/seed.sh:44-64` |
| 审计 | 契约声明了 `infra.authz.role.changed.v1`、`infra.authz.user_role.changed.v1`；outbox 表和推送泵在跑，**没有任何代码往 outbox 写**；`role_changes` 没有 actor 列 | `contracts/events/authz.events.json`；`module/module.go:66`；`grep outbox backend` 只命中分区和泵；`002_create_outbox_and_role_changes.up.sql`；`docs/design.md` Events 一节自认"This version writes neither event" |

### 3.2 逐项回答你的问题

**完整吗？** 主干完整：声明、注册即强制、本地判定、fail-closed 默认值（没配 JWKS → 403、bundle 没到 → 503）、角色到期、踢人。缺口在 §3.3。

**怎么授、怎么撤？** 授：角色加键（`POST /roles/:code/permissions`）、人加角色（可带 `expires_at`）、人加单键（建 `u:<sub>` 专属角色）。撤：角色减键、人减角色、踢人。**单键授予没有对称的撤销接口**（只能拿专属角色码去调 `DELETE /roles/u:<sub>/permissions/:key`，`http.go:40,45`）；也没有"谁持有键 K / 谁持有角色 R"的查询——"谁能关账？"这种审计问题今天答不出。

**改了多快生效？**

| 变更 | 生效路径 | 最长时延 | 证据 |
|---|---|---|---|
| 角色加/减键 | bundle 的 `roles` 直接变 | ~15 秒 | `bundle.go:14` |
| 人授/撤角色、角色到期、踢人 | `role_changes` / `expires_at` → bundle 的 `stale_since` → 401 `token_stale` → 前端静默刷新 | ~15 秒 + 一次刷新 | `repo/bundle.go:71-99`；`userroles.go:17-41` |
| **改部门** | 不写 `role_changes`，等 token 过期 | **最长 600 秒** | `repo/departments.go:79-84` 注释明说 |
| 仓库 / 法人授权 | 组件每个请求现查自己的表 | 立即 | `erp/inventory/backend/internal/service/service.go:27-30` |
| 前端按钮 | `/api/me/permissions` 直接查库 | 立即，**比后端早最多 15 秒**（按钮出现了，点下去 403） | `authz/service.go:61-85` |
| authz 宕机 | 各进程沿用最后一份 bundle | 不再收敛，直到恢复 | `bundle.go:53-55` |

15 秒对 ERP 足够（AWS IAM 也是秒级最终一致）；问题只在"改部门"这一行，见 §3.3 (d)。

**有审计吗？** 没有。事件声明了、从没发；`role_changes` 只有 `sub/role_code/change_type/changed_at`，不知道是谁做的；角色内容变更（加/减键）、建删角色、改部门、各组件的仓库/法人授权变更，**一条记录都没有**。被拒绝的请求也只在访问日志里留一个状态码（`gin.go:189-200` 不记 `sub`、不记权限键）。

**能表达"这个动作只能对自己的单子做"吗？** 不能。数据范围对一个组件的所有键一视同仁：有 `erp.sales.cancel` 的人能取消本部门及下级的**任何**订单（`erp/sales/backend/internal/service/service.go:25-35` `checkOrderInScope` 用的是 owner OR org）。要表达"能看本部门、只能取消自己的"，今天只能在组件里写特例代码。这是功能权限和数据权限的交叉点，解法在议题二（§4.5 范围档位）。

**超级管理员？** 有两个"类超级用户"，都不理想：
- `authz_admin`：只有 `infra.authz.admin` 一个键，但能给自己授任何角色——事实上的 root，却在 bundle 里看不出来；
- 种子的超级测试角色：键是种子那一刻抄进去的，**之后新加的键不会自动进来**（每加一个组件就要重跑种子），而且它绕过 REST API 直接写库（`seed.sh:44`）。生产部署没有对应物。

**服务身份？** 没有。"系统身份"的实际含义是"不带 token"，被调方的 gRPC 面不验任何东西（§5.1）。在一台机器、一个 compose 网络里这是"网络即信任边界"，但这条边界没有写进任何文档，也没有检查。

**首个管理员？** 有（`BOOTSTRAP_ADMIN_SUB`），但：本地开发留空、靠种子直接写库；`authz_admin` 和专属角色都能被管理 API 删掉（`docs/design.md` Open questions 自认），删掉最后一个管理员后整个系统再也没人能授权，只能进库手修。

### 3.3 缺口与方案

| # | 缺口 | 证据 | 方案与取舍 | 推荐 |
|---|---|---|---|---|
| a | 审计事件从不发、没有 actor | §3.1 最后一行 | ① 现在就在每个变更的同一事务里写 outbox，payload 带 `actor_sub`；② 等审计组件出现再做（现状）。① 的代价是"`version` 取什么"——用 `role_changes.id`（BIGSERIAL 单调）和给 `roles` 加 `version` 列即可；没有消费者不是不发的理由：outbox 是事实记录，消费者以后从 JetStream 回放（与 `events-consistency.md` 的结论衔接） | ①。新增 `actor_sub` 列；新增两个事件 `infra.authz.user_dept.changed.v1`、（二期）`infra.authz.scope_grant.changed.v1`；访问日志加 `sub`、`perm` 两个字段（拒绝原因可查，量大不进事件） |
| b | 超级用户随新键漂移 | `seed.sh:44-64` | ① bundle 里给一个角色写 `"*"`，SDK 认通配；② authz 自带系统角色 `superuser`，**每次同步权限目录时自动补齐全部未退役键**。① 要改三份 SDK、让"为什么他能做 X"的答案变模糊（0203 禁的是 token 里的通配，bundle 里也不该开这个口）；② 不动 SDK，bundle 仍是显式列表 | ②。种子改为授 `superuser`、走 REST API；生产上 `superuser` 默认无人持有 |
| c | 系统角色可删、最后一个管理员可撤 | `docs/design.md` Open questions | 删除/改动 `is_system` 角色 → `FailedPrecondition`；撤销后持有 `infra.authz.admin` 的人数为 0 → `FailedPrecondition` | 做 |
| d | 改部门不 stale | `repo/departments.go:79-84` | `AssignUserDepartment` 在同一事务写 `role_changes(change_type='dept_changed')`（迁移放宽 CHECK）；代价是被改的人下一次请求多一次静默刷新 | 做。功能权限 15 秒、数据权限 600 秒的不对称没有理由 |
| e | **refresh token 能当 access token 用** | refresh 与 access 同一把私钥（`tokens/tokens.go:1-9`），只有 refresh 带 `typ`；三份 SDK 都不看 `typ`（`be-sdk-go/jwt.go:24-29,50-72`、`be-sdk-ts/src/jwtVerify.ts:47-66`、python `jwt_verify.py:58`） | refresh token 有 `sub`、`iat`、`exp`（7 天），能通过验签；roles 为空所以过不了具体键，但能过所有 `Authenticated` 路由（`/api/me/permissions` 会按 sub 查库返回真实键列表、`/api/iam/logout`），且它存在 `localStorage`（前端 `iam.ts`）。修法：iam 给 access token 签 `typ: "access"`；SDK 拒绝 `typ == "refresh"`（v0.6.0），等所有在途 token 过期后再改成"必须是 access"（v0.7.0） | 做，优先级最高的一条 |
| f | 单键授予没有撤销、没有"谁持有"查询 | `http.go:40-46` | 加 `DELETE /api/admin/users/:sub/permissions/:key`、`GET /api/admin/permission-keys`（06c 需要，见 `frontend-needs.md:74`）、`GET /api/admin/permission-keys/:key/holders`、`GET /api/admin/users/:sub/access`（§4.7） | 做 |
| g | 死键：声明了、永远检查不到 | `erp/inventory/backend/internal/http/http.go:20-24`：`erp.inventory.reserve`/`.issue` 只在 gRPC 上用，而 gRPC 不判键 | ① 给 gRPC 也做键检查（议题三方案 A 的一部分）；② 承认 TCC 是系统协议、不是用户动作，键标 `deprecated`。① 的键没有对应的人——是 sales 在调，不是人 | ②。be-acceptance 加 `perm-key-usage-scan`：每个未退役键必须出现在至少一个路由注册或 `menus` 里 |
| h | 特性端点与文档矛盾 | `03-frontend.md:85` 说两个端点"只返回这个用户能看的"；`/api/tenant/features` 是 Public、返回全部已装组件（`iam-casdoor/assembly.yaml` edge_routes、`http.go:123-131`） | ① 改文档：features 是租户级、公开；② 改端点：要登录，只返回"用户至少有一个键"的组件。登录页不需要模块列表，② 才符合"不泄露买了什么"的初衷 | ②，并入 `/api/me/access`（§4.7）；`/api/tenant/features` 保留给登录前的品牌/开关，内容收窄（待拍板 Q3） |

服务身份（网络即信任边界）的处理并入议题三 §5.3。

### 3.4 一期要改的仓库（功能权限部分）

- **infra/iam-casdoor 2.0.1**：`tokens.go` 的 `appClaims` 加 `Typ string \`json:"typ"\``，签 `"access"`；`logout` 改用 `RequireUser`（议题四）。
- **infra/authz 2.1.0**（新功能，minor）：
  - 迁移 004：`role_changes` 加 `actor_sub TEXT NOT NULL DEFAULT ''`、CHECK 加 `dept_changed`；`roles` 加 `version BIGINT NOT NULL DEFAULT 1`；建系统角色 `superuser`（`is_system=true`）。
  - repo：每个写方法在同一事务里 `besdk.PublishOutbox(tx, schema, ev)`（`be-sdk-go/outbox.go:19`）；`AssignUserDepartment` 写 `role_changes`；`DeleteRole`/`RevokeRolePermission`/`GrantRolePermission` 对 `is_system` 拒绝（`u:<sub>` 例外：它只能经 `/users/:sub/permissions` 改）；`RevokeUserRole`/`RevokeAllUserRoles` 检查最后一个管理员。
  - service：`SyncPermissionCatalog` 之后 `SyncSuperuserRole`。
  - http：§3.3 (f) 的四个端点；`/api/me/access`（一期只返回 `sub`、`dept_path`、`has_dept`、`keys`、`components`；二期加档位与维度值）。
  - 契约：`authz.openapi.yaml` 只增；`authz.events.json` 只增（`actor_sub` 是新的可选字段、新 subject）。
  - `scripts/seed.sh`：去掉直接写库那一步之外的超级角色构造，改授 `superuser`。第 ① 步（首个管理员）仍直接写库，或要求本地 `.env` 配 `BOOTSTRAP_ADMIN_SUB`（待拍板 Q4）。
- **三个 SDK v0.6.0**：拒 `typ=refresh`；访问日志加 `sub`、`perm`。
- **registry**：`erp.inventory.reserve`、`erp.inventory.issue` 的 `deprecated` 列写原因（只增不改：不删行）。
- **be-acceptance**：`perm-key-usage-scan`。
- **前端 1.1.0**（06c）：`/api/me/access` 替代 features+permissions 两次请求。

### 3.5 先写的红测试（功能权限）

- be-sdk-go `TestVerify_拒绝typ为refresh的token`（用测试私钥签一个 `typ:refresh` 的 token，期望 401）；python / ts 同名。
- iam `TestSignAccessToken_带typ_access`；`TestRefreshToken_不能通过besdk验签`（端到端：拿 refresh token 打 `/api/iam/logout`，期望 401）。
- authz（真 PG，`brickkit_test_db`）：
  - `TestGrantUserRole_同一事务写outbox事件且带actor`
  - `TestGrantRolePermission_写role_changed事件且version加一`
  - `TestAssignUserDepartment_写role_changes让旧token变stale`
  - `TestDeleteRole_系统角色返回FailedPrecondition`
  - `TestRevokeUserRole_撤掉最后一个authz管理员返回FailedPrecondition`
  - `TestSyncPermissionCatalog_superuser自动获得全部未退役键且不含已退役键`
  - `TestRevokeUserPermission_撤销专属角色上的单个键`
  - `TestMeAccess_无部门的人has_dept为假`
- be-acceptance `TestPermKeyUsageScan_声明了却没有路由与菜单引用的键报错`。

---

## 4. 议题二：数据权限

### 4.1 现状与证据

| 组件 | 维度 | 值从哪来 | 分配存在哪 | 分配怎么改 | 没有分配时 | 扩大范围的特例 |
|---|---|---|---|---|---|---|
| erp/sales | `org`（`dept_path` 前缀）+ `owner` | JWT `dept_path`、`sub` | authz `user_departments` | authz `POST /users/:sub/department` | 只剩本人（R60 哨兵） | 请求参数 `view=mine\|dept`（用户自己缩小） |
| crm/opportunity | 同上 | 同上 | 同上 | 同上 | 同上 | 同上 |
| infra/workflow | `org` + `owner`（被指派人） | 同上 | 同上 | 同上 | 同上 | 键 `infra.workflow.admin`：去掉 owner 一侧、保留 org（`http.go:32`；`service.go:190-196`） |
| infra/notification | `owner`（`recipient_sub`） | JWT `sub` | — | — | — | 键 `infra.notification.admin`：**去掉 owner、看全部**（`service.go` ListRecordsAdmin；`repo/records.go:191-199`） |
| erp/inventory | `warehouse`（`mode: in`） | 本组件 `warehouse_access(sub, warehouse_id)` | **本组件** | 本组件 `/erp/inventory/warehouse-access/:sub`，键 `erp.inventory.manage_access`（`http.go:36-38`） | 什么都看不到 | 无（超级用户要逐仓授予，`inventory/scripts/seed.sh:60-61`） |
| erp/finance | `legal_entity`（`mode: in`） | 本组件 `legal_entity_access` | **本组件** | 本组件 `/erp/finance/legal-entity-access/:sub`，键 `erp.finance.manage_access`（`http.go:40-42`） | 什么都看不到 | 无 |
| 其余 | `data_scopes: none` | | | | | |

SDK 侧：`ScopeFilter{All, HasDept, Prefix, Exact, Owner, In}`（`be-sdk-go/scope.go:51-58`），`In` 注明"由组件自己查出来后组装，不归 ScopeOf 管"（`scope.go:47-50`）——**SDK 只知道 JWT 里的维度，资源维度完全在 SDK 之外**。`registry/data-scopes.tsv` 由 be-ops 派生，**运行时没有任何人读它**（只有 be-ops 自己和文档引用）。

### 4.2 两种权限混用、各组件不一致的地方（全部）

1. **用数据范围 API 取身份。** "我是谁"统统写成 `besdk.ScopeOf(ctx).Owner`：authz `/api/me/permissions`（`http.go:82`）、iam logout（`http.go:108`）、workflow 审批人（`service.go:204`）、opportunity 阶段变更人（`service.go:265`）、print 渲染人（`routes.py:67`）、inventory / finance 拿 sub 去查授权表（`service.go:28`、`service.go:37`）。身份和范围是两件事，混在一个对象里，导致议题四的 panic 问题、也让下一条成为可能。
2. **建单快照的部门取自"范围"而不是"身份"。** sales `tcc/create.go:98-107`、opportunity `service.go:206-213` 用 `scope.Prefix` 写行的 `dept_path`。今天 Prefix 恰好等于身份里的部门；一旦范围有档位（§4.5，`own` 档的 Prefix 是哨兵），快照就会写错。这是二期之前必须先修的一条。
3. **用功能权限键扩大数据范围，而且两个组件语义相反。** `infra.workflow.admin` 只去掉 owner 一侧、仍受部门限制；`infra.notification.admin` 直接看全部。两者都是"管理员运行时授一个键 = 看到更多行"，正是 0205 列为排除项的"runtime toggle"，只是换了个形式。
4. **0205 的字面已被现状违反。** 0205 排除"An admin screen for editing who can see which rows"（`0205-…md:15`），而 inventory、finance 的 `*-access` 管理 API 正是"编辑谁能看哪些行"。真实的界线不是"运行时 vs 版本"，而是"**规则**（按哪一列、哪种匹配）跟版本走，**分配**（这个人持有哪些值）是运行时数据"——部门分配从一开始就是运行时的。0205 没写出这条界线。
5. **资源维度的分配散在各组件。** 两张授权表、两套管理 API、两个 `manage_access` 键、零审计；"张三在全系统能看到什么"要分别问 authz、inventory、finance；将来 sales 也按法人限定时，要么第三份 `legal_entity_access`，要么跨组件读 finance 的表（违反 0101）。
6. **`org_id` 与 `org` 撞名。** JWT 的 `org_id` 是"默认法人/租户"（`authz.proto:49` "阶段三只有一个默认法人"，恒为 `DEFAULT_ORG_ID`），数据范围的 `org` 是部门树；finance 的 `legal_entity` 维又不用 `org_id`。三个名字两种含义。
7. **gRPC 面上数据范围的行为四种**（详见 §5.1）：Unauthenticated、Internal+ERROR、信任请求里自报的 sub、完全不过滤。
8. **范围外的单条读：resource 维答 403，org/owner 维答 404。** inventory `GetBalance` 范围外 → `ErrForbidden`（`repo/balance.go:38-46`）；sales / opportunity / workflow 读范围外 → 404（`sales/service.go:147-160`、`workflow/service.go:141-145`）。各有理由（仓库 ID 本身不保密），但规则没写进 `02-backend.md`。
9. **聚合值不受维度约束。** finance 的应收台账按 `legal_entity` 过滤，但 `GET /credit-exposure/:customer_id` 只要 `erp.finance.view`、读的是跨法人的汇总表（`service.go:125-127`、`repo/credit.go:27`）。只有一个法人时无害，多法人时是一条跨维度泄露（待确认 Q9）。
10. **数据权限变更时延不一致**：部门 600 秒、仓库/法人立即、功能权限 15 秒（§3.2 表）。
11. **BFF 双重把门。** BFF 自己声明 `infra.bff-mobile.order.view` 等 8 个键（`bff-mobile/assembly.yaml` permissions），转发到下游 REST 时下游再查 `erp.sales.view`；一个移动端用户要同时有两个键，角色配置容易漂移（待拍板 Q6）。
12. **`ScopeFilter.All` 没有消费者**，`In` 字段 SDK 从不填（R60 已记录）：SDK 的形状与组件的真实用法脱节。

### 4.3 业界对照

| 方案 | 怎么表达"看哪些行" | 分配在哪、何时改 | 适合本项目吗 |
|---|---|---|---|
| **若依 RuoYi**（RBAC + 数据权限） | 角色上一个 `data_scope`（全部 / 自定义部门 / 本部门 / 本部门及以下 / 仅本人）+ `sys_role_dept`；`@DataScope` 注解往 SQL 拼片段 | 运行时，角色管理页 | 档位模型正对口；**拼 SQL 字符串不要**（0206：静态参数化 SQL） |
| **Odoo record rules** | 每个 group × model 一条 domain 表达式，分读/写/建/删四个开关；group 规则之间 OR，全局规则 AND | 运行时，存库，ORM 注入 | "按操作区分"和"组内 OR"对口；**运行时表达式不要**（AI 读不懂也测不了，authz `design.md` 已排除） |
| **SAP 授权对象** | 一个授权 = 活动字段（ACTVT）+ 组织字段（BUKRS 公司代码、WERKS 工厂）的值，绑在角色上 | 运行时，PFCG | "资源维度取值绑在角色上"对口；**把功能和数据塞进同一个对象**不要（authz `design.md` 已排除） |
| **Dynamics 365** | 每个 privilege（Create/Read/Write…）× depth（用户 / 业务部门 / 父子部门 / 组织） | 运行时，安全角色 | **"动作 × 档位"正是"只能对自己的单子做"的标准答案**；团队/共享不要 |
| **Salesforce** | OWD + 角色层级 + 共享规则（物化共享表） | 运行时，重算昂贵 | 不要（0205 的反例） |
| **PostgreSQL RLS** | `CREATE POLICY` | 随迁移 | 不要（0206） |
| **ABAC（OPA / Cedar）** | 任意属性上的策略语言；列表过滤要靠部分求值翻成 SQL | 运行时策略 | 我们本来就是"固定属性的 ABAC"（sub、dept_path、维度值），把策略编译进代码；通用策略语言换来的灵活性用不上，代价是列表过滤 |
| **ReBAC（Zanzibar / OpenFGA / SpiceDB）** | 关系元组（每个对象一条 ACL），`ListObjects` | 中心服务、每请求问 | 不要：ERP 的可见性是"按组织切片"不是"按文档共享"；违反 0202（每请求网络跳）、不适合单机（authz `design.md` 已排除） |

结论：本项目已经站在"若依式 RBAC + 数据范围"这条主线上，缺的两块恰好是若依和 Dynamics 都有的：**档位挂在角色上**、**资源维度取值挂在角色上**。补上它们不需要 RLS、不需要表达式、不需要中心决策服务，SQL 仍然是静态的。

### 4.4 方案

**分配放哪（资源维度）**

| | 做法 | 优点 | 缺点 |
|---|---|---|---|
| A 现状 + 规范化 | 各组件保留 `*_access` 表，统一表结构、统一管理 API 形状、补审计事件 | 不动 authz、不动 bundle | 第 5、10 条不解决；每加一个资源维度的组件就多一套；"一个人的全部范围"仍要 N 次查询 |
| B 进 authz、进 **JWT claims** | `ResolveClaims` 带 `scopes: {warehouse: [...]}` | 组件零查询 | 违反 0203（"data-scope rules inside the token"）；值多时撑大 token（0203 的 431 教训）；改分配要靠 stale 让所有人重新签 |
| C 进 authz、进 **bundle**，**挂在角色上** | `role_scope_values(role_code, dimension, value)`；bundle 加 `grants`；人通过角色（含 `u:<sub>` 专属角色）获得取值 | 0202 / 0203 原样成立（JWT 仍只有 roles）；bundle 大小随角色数增长、不随人数增长（除了专属角色）；15 秒生效；authz 一处可查、一处审计；组件不再有授权表和管理 API | bundle 格式扩展；inventory / finance 要迁移；authz 不认识仓库 ID（只存不透明字符串） |
| D 进 authz、组件每请求 gRPC 问 | `ResolveScopes(sub, dim)` | 实现简单 | 违反 0202（每请求一跳）；authz 抖动 = 全系统数据权限抖动 |

**档位（org / owner 维）**

| | 做法 | 优点 | 缺点 |
|---|---|---|---|
| L0 现状 | 一个组件的所有键共用"owner OR 本部门及以下"；扩大靠 `.admin` 键 | 简单 | 不能表达"只能取消自己的"；`.admin` 语义各组件自定 |
| L1 档位挂在（角色, 键）上 | 角色授键时带档位 `own` / `subtree` / `all`；一个人对键 K 的档位 = 授予 K 的各角色档位的最大值（仍是纯并集：并集的序上取最大） | 对标若依 data_scope + Dynamics depth；`.admin` 退役；SDK 用值层面的手法（档位不足时把 Prefix 置为哨兵）让现有 SQL 不改就收紧 | bundle 格式扩展；0205 要改写；`all` 档需要组件加一个显式分支 |
| L2 档位挂在角色上（若依原样） | 一个角色一个档位 | 管理界面最简单 | "看本部门、只取消自己的"要拆两个角色——其实 L1 在管理界面上也可以按角色设默认档位、个别键覆盖，二者可以合一 |

### 4.5 推荐：C + L1（"分配进 authz，规则跟版本"）

**一句话**：组件的 `assembly.yaml` 声明"我按哪些维度、哪一列过滤"（规则，跟版本）；authz 存"每个角色对每个键的档位、对每个资源维度持有哪些值"（分配，运行时）；bundle 把分配发到每个进程；SDK 按"本次路由的权限键"求出 `ScopeFilter`；组件 SQL 仍是静态参数化的。

**数据模型（authz 迁移 005，二期）**

```sql
-- 维度目录：来自 registry/data-scopes.tsv（DATA_SCOPE_CATALOG: file://registry/data-scopes.tsv），
-- 启动时同步，与 PERMISSION_CATALOG 同一套做法。管理界面据此知道有哪些维度、哪些键需要档位。
CREATE TABLE scope_dimensions (
    dimension       TEXT PRIMARY KEY,          -- org / owner / warehouse / legal_entity
    kind            TEXT NOT NULL CHECK (kind IN ('identity', 'resource')),
    owner_component TEXT NOT NULL DEFAULT ''   -- 资源维度的取值归谁（warehouse → erp/inventory）
);
-- 档位：只对"所属组件声明了 org 或 owner 维"的键有意义
CREATE TABLE role_key_levels (
    role_code      TEXT NOT NULL REFERENCES roles(code) ON DELETE CASCADE,
    permission_key TEXT NOT NULL,
    level          TEXT NOT NULL CHECK (level IN ('own', 'subtree', 'all')),
    PRIMARY KEY (role_code, permission_key),
    FOREIGN KEY (role_code, permission_key) REFERENCES role_permissions(role_code, permission_key) ON DELETE CASCADE
);
-- 资源维度取值：'*' 是显式的"全部"，只能显式授予，从不是默认值
CREATE TABLE role_scope_values (
    role_code  TEXT NOT NULL REFERENCES roles(code) ON DELETE CASCADE,
    dimension  TEXT NOT NULL REFERENCES scope_dimensions(dimension),
    value      TEXT NOT NULL,
    PRIMARY KEY (role_code, dimension, value)
);
```

**bundle 线上格式（只增：旧 SDK 忽略 `grants`）**

```json
{
  "roles": { "dev_sales_rep": ["erp.sales.view", "erp.sales.cancel"] },
  "stale_since": { "u_123": 1759400000 },
  "grants": {
    "dev_sales_rep":  { "levels": { "erp.sales.view": "subtree", "erp.sales.cancel": "own" } },
    "dev_wh_south":   { "values": { "warehouse": ["7"] } },
    "superuser":      { "default_level": "all", "values": { "warehouse": ["*"], "legal_entity": ["*"] } }
  }
}
```

**求值规则（SDK，纯函数，三份同构）**

- 档位：对路由键 K，取所有"授予 K 的角色"的档位最大值（`own < subtree < all`）；授予了 K 但没写档位 → 角色的 `default_level`，再没有 → `own`（fail-closed）。`Authenticated` 路由 → `own`。
- 取值：对维度 D，取所有"授予 K 的角色"在 D 上的值的并集；含 `*` → `all=true`；一个都没有 → 空列表（什么都看不到）。**按键求值**而不是按人求值：仓管的"查看"角色给了南北两仓、"调整"角色只给了南仓，那么调整只能调南仓——这是 SAP 授权对象的表达力，管理上仍是若依式的"给角色配"。
- 与身份合成 `ScopeFilter`：

| 档位 | `Owner` | `Prefix` | `All` |
|---|---|---|---|
| `own` | sub | `NoDeptPath`（哨兵） | false |
| `subtree` | sub | 身份的 `dept_path`（无部门时哨兵，R60 不变） | `dept_path == "/"` |
| `all` | sub | `"/"` | true |

  现有的 `owner_id = @owner OR dept_path LIKE @prefix || '%'` **一行不改**就对 `own` 档收紧成"只剩本人"（与 R60 同一个值层面 fail-closed 手法）；只有 `all` 档要组件加一个显式分支 `@all OR …`（否则 `"/"` 前缀匹配不到 `dept_path = ''` 的行，只会少看、不会多看）。

**SDK API（Go，Python / TS 同形，见 §6）**

```go
type ScopeLevel string // "own" | "subtree" | "all"

type ScopeFilter struct {
    Level   ScopeLevel
    All     bool
    HasDept bool
    Prefix  string // 永不为空串
    Exact   string // 永不为空串
    Owner   string
    values  map[string]valueSet
}
// Values 取资源维度的授权值。未授予的维度返回 (nil, false)：什么都看不到。
func (f ScopeFilter) Values(dim string) (ids []string, all bool)
```

**`assembly.yaml` 不需要新字段**：`data_scopes` 已经说明了维度和列；"哪些键需要档位"由 authz 从两份目录推导（键的 `owner_component` 声明了 org/owner 维 → 需要档位）。be-ops 只多一条校验：资源维度名全局唯一归属（`warehouse` 只能有一个 `owner_component`，其余组件只能"使用"它）——`data-scopes.tsv` 加一列 `role: owner|uses`（待拍板 Q8）。

**取值的选择器**：authz 不认识仓库，管理界面选仓库时调维度主人的接口。inventory 保留 `erp.inventory.manage_access` 键，含义改成"能列出全部仓库以便分配"（`GET /erp/inventory/warehouses?all=true`）——键不改名、不退役，只是不再有授权表。仓库删除后 authz 里留下的悬空值无害（匹配不到任何行）。

**与决策的关系**

- 0202、0203、0204、0206：原样成立（JWT 仍只带身份；决策仍在进程内；纯并集；静态 SQL、无 RLS、无共享引擎）。
- 0205：改写，另立 **0207 "范围的规则随版本，范围的分配在 authz"**。草稿：
  - Decision：组件在 `assembly.yaml` 声明按哪些维度、哪一列过滤，随版本发布；一个角色对每个键的档位（`own`/`subtree`/`all`）和它持有的资源维度取值，由管理员在 infra/authz 运行时维护，随 bundle 下发。
  - What this rules out：任意表达式或可编辑的过滤规则；"把这一条记录共享给某人"（仍是改 `owner_id` 的业务功能）；组件自建授权表或分配管理 API；用一个权限键来扩大数据范围；把档位或取值放进 JWT。
  - Revisit only if：档位三档不够用（典型是"只看本部门、不含下级"），且有真实客户需求。
- 本仓库已有的"部门分配在 authz"恰好是这条决策的先例，0207 只是把它推广到资源维度和档位。

**为什么这个设计对判据最好**：组件可替换（换一个 inventory，只要读 `ScopeFrom(ctx).Values("warehouse")`，不用迁授权数据）；数据库可替换（SQL 仍是静态参数）；对 AI 友好（"谁能看什么"只在 authz 一处，组件里没有授权表、管理 API、`.admin` 特例）；快速定位（一个端点答出一个人的全部范围）；也符合 principle 1：inventory 单独跑本来就要 `AUTHZ_BUNDLE_URL`，不新增依赖边。

### 4.6 一个人的统一视图、"为什么我看不到"

- `GET /api/me/access`（authz，`Authenticated`）：

  ```json
  {
    "sub": "u_123",
    "dept": { "path": "/1/12/", "has_dept": true },
    "components": ["erp/sales", "infra/workflow"],
    "keys": { "erp.sales.view": { "level": "subtree" }, "erp.sales.cancel": { "level": "own" } },
    "values": { "warehouse": [], "legal_entity": ["*"] }
  }
  ```

  前端据此在页面顶部给出解释，不需要每个页面问后端：`level` ≥ `subtree` 且 `has_dept=false` → "尚未分配部门，只能看到自己创建的单据"；页面依赖的资源维度为空 → "尚未分配仓库，请联系管理员"；`level=own` → "只显示你负责的"。
- `GET /api/admin/users/:sub/access`（`infra.authz.admin`）：同一结构，加"来自哪个角色"（`granted_by`），回答"他为什么能看到 / 为什么看不到"——纯并集保证答案唯一（0204 的初衷）。
- 错误体加机器可读原因（SDK 统一）：`403 {"error": "...", "reason": "missing_key", "key": "erp.sales.confirm"}`；`403 {"reason": "out_of_scope", "dimension": "warehouse"}`。**范围外的单条读仍答 404**（不泄露存在性）；只有请求参数本身就是维度值（`warehouse_id=7`）时答 403。这条规则写进 `02-backend.md`，统一 §4.2 第 8 条。

### 4.7 迁移

本项目还没有生产数据（`dept-scope-analysis.md` §5.1"生产环境还没有数据"），迁移只涉及种子：

1. authz 2.2.0 上线新表、bundle `grants`、管理 API（`PUT /api/admin/roles/:code/levels/:key`、`POST/DELETE /api/admin/roles/:code/values/:dimension/:value`、单人版 `/api/admin/users/:sub/values…` 走专属角色）、`DATA_SCOPE_CATALOG` 配置键；迁移把现有 `role_permissions` 里"需要档位的键"一律写 `subtree`（保持今天的行为）。
2. SDK v0.7.0 读 `grants`；bundle 没有 `grants` 字段（旧 authz）时：档位按 `subtree`（保持今天）、资源维度取值为空（fail-closed）。
3. inventory / finance 2.1.0：`Values()` 与本地表**取并集**过渡一版（行为只会不变或变宽到"authz 里也授了的"），本地管理 API 在 openapi 里标 `deprecated`；种子改为调 authz。下一个大版本（3.0.0）删表删端点——或者既然没有生产数据，在 2.1.0 直接删（0302 要求契约只增，需要你决定是否破例，Q7）。
4. sales / opportunity / workflow / notification 2.1.0：加 `All` 分支；workflow、notification 的 `/admin/*` 路由改为普通路由 + `all` 档（旧路由保留、换成同一实现，键 `infra.workflow.admin`、`infra.notification.admin` 标 `deprecated`，已授予它们的角色由迁移自动转成 `all` 档）。

### 4.8 各组件改动与版本（数据权限部分）

| 仓库 | 一期 | 二期 |
|---|---|---|
| be-sdk-go / python / ts | v0.6.0：`User` / `ScopeFrom`（§6）；`ScopeFilter` 字段不变 | v0.7.0：`Level`、`Values()`、`grants` 求值；`In` 字段删除（无消费者） |
| infra/authz | 2.1.0（§3.4） | 2.2.0：迁移 005、bundle `grants`、管理 API、`DATA_SCOPE_CATALOG`、`/api/me/access` 完整版、`scope_grant.changed` 事件 |
| erp/sales、crm/opportunity | 2.0.1：快照部门改取 `User.DeptPath`（§4.2 第 2 条）；`RequireUser` | 2.1.0：`All` 分支；`cancel`/`confirm` 等写路径按各自键的档位判（`checkOrderInScope` 用 `ScopeFrom` 而不是固定 OR） |
| infra/workflow | 2.0.2：`RequireUser`；审批人取 `User.Sub` | 2.1.0：`all` 档替代 `.admin` |
| infra/notification | 2.0.1：`RequireUser` | 2.1.0：`all` 档替代 `.admin` |
| erp/inventory | 2.0.1：`RequireUser`（gRPC 不再 Internal） | 2.1.0：`Values("warehouse")` ∪ 本地表；种子改走 authz |
| erp/finance | 2.0.1：删 `requireUser` 的 recover | 2.1.0：`Values("legal_entity")` ∪ 本地表；Q9 的信用敞口 |
| be-ops | — | `data-scopes.tsv` 加 `role` 列与唯一归属校验 |
| registry | 一期：两个死键标 `deprecated` | 二期：`infra.workflow.admin`、`infra.notification.admin` 标 `deprecated` |
| docs | `02-backend.md` Data scopes 加"404/403 规则""快照取身份" | 0205 加指向 0207 的说明；新 0207；`02-backend.md` Data scopes 重写"分配在 authz"；`03-frontend.md` 改用 `/api/me/access` |
| frontend | — | 1.1.0：范围说明横幅（06c） |

外壳：`go.mod` 钉成员里最高的 SDK；v0.7.0 对旧成员的影响只有"`own` 档让 Prefix 变哨兵"，而旧成员在 authz 2.2.0 迁移后全部是 `subtree`，行为不变。

### 4.9 先写的红测试（数据权限）

一期：
- sales `TestCreateOrder_快照部门取身份不取范围`：用 `besdktest.WithUser` 构造有部门的用户、并把范围强制成 `own`（`besdktest.WithScopeLevel`），断言新订单 `dept_path` 是身份里的部门而不是哨兵。opportunity 对称 `TestCreateOpportunity_快照部门取身份不取范围`。
- `02-backend.md` 的 404/403 规则：workflow / sales 现有测试已覆盖 404；inventory 加 `TestGetBalance_请求参数里的仓库未授权答403且reason为out_of_scope`。

二期：
- SDK：`TestScopeFrom_多个角色授同一个键时取最高档位`、`TestScopeFrom_own档时Prefix是哨兵且Owner是本人`、`TestScopeFrom_授了键没写档位按own`、`TestScopeFrom_Authenticated路由按own`、`TestValues_未授予的维度为空且all为假`、`TestValues_星号表示全部`、`TestValues_按路由键求值不同键取值不同`、`TestBundle_没有grants字段时档位按subtree且取值为空`。
- authz：`TestBundle_带出角色的档位与维度取值`、`TestGrantRoleValue_幂等且写scope_grant事件`、`TestMigration005_既有授权的档位一律为subtree`、`TestAdminUserAccess_每项都标出来自哪个角色`。
- inventory：`TestListBalances_只看到bundle授予的仓库`、`TestListBalances_星号看到全部`、`TestAdjust_调整角色只授南仓时调北仓Forbidden`。finance 对称。
- sales：`TestCancelOrder_cancel档位own时取消同部门别人的订单Forbidden`、`TestListOrders_view档位all看得到无部门的行`、`TestListOrders_view档位own时view参数为dept也只看到本人`。opportunity 对称。
- workflow / notification：`TestListTasks_all档看到全部部门`、`TestListRecords_all档等同旧admin视图`、`TestAdminRoute_旧admin键迁移后行为不变`。

---

## 5. 议题三：gRPC 上的用户身份

### 5.1 现状与证据

**出站：Go 的 `UserClient` 在 REST 路径上什么都不转发。** `be-sdk-go/client.go:23-38` 只从 `metadata.FromIncomingContext(ctx)` 取 `authorization`——那是 gRPC 入站请求才有的；Gin 请求的 ctx 里没有它，`RequirePermission` 也只存了解析后的 Claims、没存原始 token（`authz.go:174`）。单元测试用 `metadata.NewIncomingContext` 造 ctx（`client_test.go:56-57`），恰好绕开了真实场景。于是 sales、opportunity 的全部 `UserClient` 调用（`erp/sales/backend/internal/client/client.go:49-55`、`crm/opportunity/backend/internal/client/client.go:67`）实际上都是"系统调用"。opportunity 的设计文档自己记下了（`crm/opportunity/docs/design.md:174`）。`02-backend.md:122` 说"it forwards the caller's token, so the callee applies the caller's data scope"——**对现有每一个 Go 调用方都不成立**。Python / TS 的 `user_client` / `userClient` 显式收 `auth` 参数（`be-sdk-python/besdk/client.py`、`be-sdk-ts/src/client.ts:67-77`），确实会转发，但被调方不验。

**入站：没有任何身份检查。** `standalone.go:215` 只挂 `grpcRecoveryInterceptor`；外壳复用同一个 `ServeExtraPort`（`shell.go:87-90`）。

**同一种情况，四种结果：**

| 组件 | 面向用户的 rpc | 没有用户身份时 | 证据 |
|---|---|---|---|
| erp/finance | Close/Reopen/Lock、PostManualEntry、ReverseEntry、GetEntry、ListEntries、ListARLedger | `Unauthenticated`（就地 recover `ScopeOf` 的 panic） | `internal/grpc/grpc.go:28-44`；`grpc_test.go:58` |
| erp/sales | Create/Confirm/Cancel/Ship、GetOrder、ListOrders | `Unauthenticated`（同上） | `internal/grpc/grpc.go:27-46`；`module/grpc_identity_test.go:18` |
| erp/inventory | Receive、Adjust、GetBalance、ListMovements | `ScopeOf` panic → recovery → `Internal`，打一行 ERROR | `internal/service/service.go:19-30` |
| crm/opportunity | Create/Update/ChangeStage/MarkWon/MarkLost、Get、List | 同上，`Internal` | `crm/opportunity/docs/design.md:174` |
| infra/notification | GetPreferences / SetPreferences | **信任请求里自报的 `req.Sub`** | `internal/grpc/grpc.go:174-190` |
| mdm/customer、mdm/product | Create、Update、SetStatus、AddContact | **不检查任何东西**：网络上任何进程都能建客户、改产品，没有权限键 | 两者 grpc 面无 `ScopeOf`、无键检查 |
| infra/print（Python） | Render | `actor` 留空 | `infra_print/grpc/server.py:3` |
| infra/workflow | ListTasks | 系统视图，显式 `AllDepts`（R60） | `internal/service/service.go:126-137` |

**BFF 早就做出了选择**：有数据权限的字段走 REST 转发 Authorization，只有 `data_scopes: none` 的客户、产品走 gRPC（`bff-mobile/assembly.yaml` data_scopes 注释、`src/clients/restForward.ts:1-11`）。

### 5.2 方案

**A. 在 gRPC 上透传并验证用户 token。**
- SDK：服务端 unary/stream 拦截器验签 JWT（同一个 verifier）、查 stale、把 `User` 放进 ctx；每个面向用户的 rpc 声明权限键（proto option `(be.perm) = "erp.sales.confirm"` 或模块里一张 `method → key` 表），拦截器判键；`RequirePermission` 把原始 token 存进 ctx，`UserClient` 从那里取。
- 外壳：成员之间仍走回环 gRPC（principle 1 成立）；每一跳本地验签一次，JWKS、bundle 进程级共享（`InitShellAuthz`，`shell.go:72`），开销很小。
- 代价：每个用户 rpc 多一套键声明和 gate；同一条业务规则要在两个传输上各测一遍；token 600 秒过期，长链路（TCC 补偿、重试）中途会 401；事件 handler 天然没有 token，照样需要系统路径——所以"系统调用"这个概念并不会消失，只是多了一种。**今天没有任何调用方需要它**：前端走 REST，BFF 已改走 REST，组件间调用全部是系统协议（TCC、BatchGet、状态查询、建待办）。

**B. gRPC 只是组件间系统协议；用户面只走 REST。**
- 规则：gRPC 上的调用者恒为"系统主体"（同一个项目网络里的组件）；gRPC 只承载三类 rpc——①`data_scopes: none` 的数据；②系统协议（TCC 的 Reserve/Confirm/Cancel、建待办、关账检查）；③按 ID 补全（BatchGet），调用方只能拿**它自己合法持有的 ID** 去补全，结果不得超出用户本来能看到的范围展示给用户。面向用户、受数据范围约束的读写只在 REST。
- 已经在契约里的用户 rpc（0302 只增不删）保留，统一由 SDK 返回 `Unauthenticated`，组件不再各写各的。
- 用户请求路径上要读别的组件的受限数据（BFF 就是这种情况）：走 REST 并透传 Authorization——SDK 提供助手，仍是真实 HTTP（principle 1 成立）；外壳里也是打成员自己的 HTTP 端口（`ShellModuleConfig.HTTPPort`，`shell.go:21-27`）。
- 审计线索：系统调用如果发生在某个用户请求之内，SDK 自动附 `be-actor-sub` metadata，被调方用 `besdk.SystemFrom(ctx).ActorSub` 记"谁触发的"（入库流水的操作人等）。它不验签——与系统调用本身同一个信任级别：网络上的对端本来就能直接调 Reserve，伪造 actor 并不更糟；它只用于记录，从不用于授权。
- 代价：`02-backend.md` 的 UserClient/SystemClient 一节要重写；`system-client-scan` gate 的前提变了，要换成别的保护（见下）；将来真要"在 gRPC 上以用户身份读受限数据"时要回来重新设计（写进 Revisit）。

**C. 混合：转发 token、验签后只取 actor，不做数据范围。** 比 B 多一套验签和"token 有时有、有时过期"的不确定性，换来的只是 actor 可信——而在 B 的信任模型下 actor 本来就不需要比调用本身更可信。不推荐。

| | A 透传+验证 | B 系统专用 | C 混合 |
|---|---|---|---|
| 与现实的差距 | 大：要新建整套机制 | 小：把现状写成规则 | 中 |
| principle 1 / 外壳 | 成立 | 成立 | 成立 |
| 对 AI 友好 | 两个传输、两套判键 | 一条规则：人走 REST，组件走 gRPC | 一般 |
| 新代码量 | SDK 拦截器 + proto option + gate + 每个 rpc 的键 + 双传输测试 | SDK 拦截器（只标主体）+ REST 助手 | 介于两者之间 |
| 安全 | 用户 rpc 有键 | mdm 写 rpc 收紧成 Unauthenticated；系统面靠网络边界 | 同 B |

### 5.3 推荐：B

**SDK API（Go；Python / TS 同形）**

```go
// 服务端：SDK 的 gRPC server（standalone 与外壳共用的 serveExtraPort）统一挂 identityInterceptor，
// 在 recovery 之后：把 ctx 标成系统主体；读可选的 be-caller（调用方组件 ID）与 be-actor-sub。
type System struct {
    Caller   string // 调用方组件 ID（调用方 SDK 自动附上；仅用于日志/审计）
    ActorSub string // 触发这次系统调用的用户 sub；没有就是空串。只记录，不授权
}
func SystemFrom(ctx context.Context) (System, bool)

// 客户端：唯一的 gRPC 拨号函数。永远是系统身份；ctx 里有用户时自动附 be-actor-sub。
func Dial(ctx context.Context, cfg Config, dep, extra string) (*grpc.ClientConn, error)

// Deprecated: 等同 Dial。UserClient 从未在 REST 路径上转发过 token（client.go:29-33）。
func UserClient(ctx context.Context, cfg Config, dep, extra string) (*grpc.ClientConn, error)
// Deprecated: 等同 Dial(context.Background(), …)。
func SystemClient(cfg Config, dep, extra string) (*grpc.ClientConn, error)

// 用户请求路径上读别的组件的受限数据：REST，透传调用者原始 Authorization。
// ctx 里没有用户（事件 handler、gRPC 系统调用）时返回 Unauthenticated，不会悄悄以系统身份调。
func UserHTTP(ctx context.Context, cfg Config, dep string) (*UserHTTPClient, error)
type UserHTTPClient struct{ /* baseURL、*http.Client、auth */ }
func (c *UserHTTPClient) Do(req *http.Request) (*http.Response, error) // 自动加 Authorization、X-Request-Id、traceparent
```

`RequirePermission` 额外把原始 token 存进 ctx 的私有键（不进 `User`，免得被日志打印）。

**保护手段换成什么**：`system-client-scan` 退役（它的前提"UserClient 会透传"不成立）。替代：①约定每个组件对它的每个面向用户 rpc 有一条"经 gRPC 调答 Unauthenticated"的 L2 测试（finance `grpc_test.go:58` 的形状），be-acceptance 的 `datascopetestscan` 扩一个信号；②`UserHTTP` 在没有用户时报错而不是降级；③网络边界写进 `02-backend.md`：gRPC 端口从不进 `edge_routes`、从不经网关暴露，K8s 部署给出 NetworkPolicy 模板（`brickkit-deploy`）。真正跨信任边界部署时（多租户、对端不可信），再引入服务 token（iam 用 client-credentials 签 `sub: svc:<component-id>`），拦截器把它验成 `System.Caller`——API 不变，这是本设计留的扩展点。

**为什么不是 A**：A 要建的机制今天没有调用方，却让每个面向用户的 rpc 变成"两套传输、两套判键、两套测试"；而 B 只是把已经发生的事实写成规则、让 SDK 统一行为。Revisit 条件：出现一个必须以用户身份、在 gRPC 上读另一个组件受限数据、且 REST 无法满足（流式、超大载荷）的真实需求。

### 5.4 各组件改动与版本

| 仓库 | 改动 | 版本 |
|---|---|---|
| be-sdk-go | `identityInterceptor`、`SystemFrom`、`Dial`、`UserHTTP`、原始 token 存 ctx；`UserClient`/`SystemClient` 标 Deprecated；`client_test.go` 加真实 Gin 路径的用例 | v0.6.0 |
| be-sdk-python | 同上（`grpc.aio` 服务端拦截器、`dial`、`user_http`（httpx）） | v0.6.0 |
| be-sdk-ts | `dial`、`userHttp`（fetch）；BFF 的 `restForward.ts` 换成它 | v0.6.0 |
| erp/sales | 删 `grpc.go:27-46` 的 recover，改 `RequireUser`；`client.go` 统一 `Dial`（删掉 `*System` 变体的区分，注释改成"全部是系统协议"） | 2.0.1 |
| erp/finance | 同上，`grpc.go:28-44` | 2.0.1 |
| erp/inventory | service 层 `RequireUser`：Receive/Adjust/GetBalance/ListMovements 经 gRPC 答 Unauthenticated（今天 Internal）；入库流水的操作人取 `SystemFrom(ctx).ActorSub` / `User.Sub` | 2.0.1 |
| crm/opportunity | 同 inventory；`client.go:67` 改 `Dial`；`design.md:174` 那条未决问题关闭 | 2.0.1 |
| infra/workflow | 建待办的操作人记 `ActorSub` | 2.0.2 |
| infra/notification | `Get/SetPreferences(req.Sub)` 明确标为系统协议（注释 + design.md）；行为不变 | 2.0.1（与议题四同批） |
| mdm/customer | gRPC 的 Create/Update/SetStatus/AddContact 改 `RequireUser` → Unauthenticated（**行为收紧**：今天任何对端都能写）。先确认没有调用方（种子脚本是否用 grpcurl 写，Q5） | 2.0.2 |
| mdm/product | 同上 | 2.0.1 |
| infra/print | `actor` 取 `system_from().actor_sub` | 2.0.1 |
| infra/bff-mobile | `restForward.ts` 换 `userHttp`；gRPC 客户端换 `dial` | 2.0.1 |
| be-acceptance | 退役 `system-client-scan`；`datascopetestscan` 加"gRPC 用户 rpc 答 Unauthenticated"信号 | 新 minor |
| docs | `02-backend.md` "Calling other components" 重写；`AGENTS.md` 易错点表"Use `besdk.SystemClient` on a path that serves a user request"一行改成"Show data from a gRPC BatchGet for IDs the user does not legitimately hold"；新决策 **0208 "gRPC 是组件间的系统协议"** | — |

### 5.5 先写的红测试

- be-sdk-go `TestUserClient_在Gin请求路径上也透传Authorization`——**先写这条，它在 v0.5.0 上是红的**，用来在提交记录里固定"UserClient 从没在 REST 路径上转发过"这个事实；随后按 B 把它改成 `TestDial_Gin请求路径上附be_actor_sub而不附Authorization`（单独提交，说明原因）。
- be-sdk-go `TestIdentityInterceptor_gRPC调用的ctx是系统主体且UserFrom为false`、`TestIdentityInterceptor_be_actor_sub进SystemFrom`、`TestUserHTTP_透传调用者Authorization到下游REST`、`TestUserHTTP_没有用户时返回Unauthenticated`。Python / TS 同名。
- inventory `TestGRPC_Receive没有用户身份答Unauthenticated而不是Internal`（今天红）。opportunity `TestGRPC_面向用户的rpc答Unauthenticated`（今天红）。
- mdm/customer `TestGRPC_Create没有用户身份答Unauthenticated`（今天红：会建成功）；product 对称。
- sales / finance：现有 `grpc_identity_test.go:18`、`grpc_test.go:58` 在删掉 recover 之后保持绿（回归）。
- 外壳（T22 组装后）：`go-core` 里 sales → inventory 的 Reserve 走回环 gRPC，inventory 记下的操作人等于发起确认的用户。

---

## 6. 议题四：Claims 读取 API

### 6.1 现状

- Go：`claimsFromContext` 是私有的（`authz.go:105-112`）；对外只有 `ScopeOf(ctx)`，取不到就 panic（`scope.go:74-81`），注释的理由是"只可能是编程错误"——在 REST 上成立，在 gRPC 上不成立（gRPC 没有身份是调用方的事，不是编程错误）。于是 finance、sales 各写一份 `requireUser` 就地 recover（`finance/internal/grpc/grpc.go:34-44`、`sales/internal/grpc/grpc.go:36-46`，注释都写着"SDK 没有不 panic 的 Claims 读取函数"）；inventory、opportunity 没写，panic 变 `Internal` 加一行 ERROR。
- 拿身份只能借道范围：`ScopeOf(ctx).Owner`（§4.2 第 1 条）；拿不到 `Roles`、`OrgID`、`IssuedAt`；没有 `HasPermission`（同一路由内按键分支，例如"有确认权的人才看到成本价"）。
- 测试：`ContextWithClaims` 是导出的生产包函数，只靠注释约束"只许出现在 _test.go"（`authz.go:114-126`）。
- Python：ContextVar 里只存 `ScopeFilter`、不存身份（`besdk/scope.py:78-112`，`authz.py:152`）；`scope_of()` 抛 `RuntimeError`。
- TS：context 对象上只挂 `ScopeFilter`（`src/scope.ts:98-124`），`scopeOf` 抛普通 `Error`。

### 6.2 方案

| | 形状 | 取舍 |
|---|---|---|
| a | 只加 `ClaimsFrom(ctx) (Claims, bool)` | 最小改动；但"没有身份该答什么错"仍由每个组件自己决定，身份和范围仍混在 `ScopeFilter` |
| b | **`UserFrom` (bool) + `RequireUser` (error) + `ScopeFrom` (error) + `HasPermission`**，身份是 `User`、范围是 `ScopeFilter`，分开 | 一个错误值在 REST 映射成 401、在 gRPC 就是 `Unauthenticated`，组件一行解决；身份与范围分开，二期档位不会误伤快照（§4.2 第 2 条） |
| c | 主体枚举 `Caller{Kind: User\|System\|Anonymous}` 一个函数 | 表达力最强，但每个调用点都要 switch；系统主体已经有 `SystemFrom`（§5.3），不必合并 |
| d | 显式参数（业务函数签名带 `User`） | 编译期保证，但 service 层所有签名都要改，且 Go/Python 的 ctx 惯例被打破 |

### 6.3 推荐：b

**Go（be-sdk-go v0.6.0）**

```go
// User 是本地验签后的调用者身份。只读；DeptPath 原样保留，要不要算"有部门"用 HasDept。
type User struct {
    Sub      string
    Roles    []string
    DeptPath string
    OrgID    string
    IssuedAt time.Time
}
func (u User) HasDept() bool // strings.HasPrefix(DeptPath, "/")

// UserFrom：ctx 里有经 RequirePermission 验签的用户时 ok=true。从不 panic。
func UserFrom(ctx context.Context) (User, bool)

// RequireUser：没有用户时返回 ErrUnauthenticated（= status.Error(codes.Unauthenticated, …)），
// gRPC handler 直接 return 它；Gin 的错误映射把它变成 401。service 层的标准入口。
func RequireUser(ctx context.Context) (User, error)
var ErrUnauthenticated error

// ScopeFrom：RequireUser + 本次路由权限键对应的范围（一期 = 今天的 ScopeOf 结果；二期加档位与取值）。
func ScopeFrom(ctx context.Context) (ScopeFilter, error)

// HasPermission：当前用户是否持有 key。bundle 未就绪、没有用户 → false（fail-closed）。
func HasPermission(ctx context.Context, key PermKey) bool

// Deprecated: 用 ScopeFrom。保留 panic 语义一个版本周期，给 2.0.x 组件迁移时间。
func ScopeOf(ctx context.Context) ScopeFilter
// Deprecated: 用 besdktest.WithUser。
func ContextWithClaims(ctx context.Context, claims Claims) context.Context
```

```go
// package besdktest（github.com/brickKit/be-sdk-go/besdktest）——只给测试用；be-acceptance 扫生产代码里的导入。
func WithUser(ctx context.Context, u besdk.User, opts ...Option) context.Context
func WithScopeLevel(level besdk.ScopeLevel) Option          // 二期
func WithValues(dim string, values ...string) Option        // 二期
func WithPermissions(keys ...besdk.PermKey) Option          // 让 HasPermission 在测试里可控
```

**Python（be-sdk-python v0.6.0）**

```python
@dataclass(frozen=True)
class User:
    sub: str
    roles: tuple[str, ...]
    dept_path: str
    org_id: str
    issued_at: datetime
    @property
    def has_dept(self) -> bool: ...

class Unauthenticated(Exception): ...   # FastAPI 异常处理器 → 401；gRPC 拦截器 → UNAUTHENTICATED

def current_user() -> User | None
def require_user() -> User             # 没有用户时 raise Unauthenticated
def scope() -> ScopeFilter             # 同上
def has_permission(key: PermKey) -> bool
# 弃用：scope_of()
# besdk.testing.with_user(user, **opts) -> ContextManager
```

ContextVar 从"只存 ScopeFilter"改成存 `(User, ScopeFilter, 原始 token)`。

**TypeScript（be-sdk-ts v0.6.0）**

```ts
export interface User { sub: string; roles: readonly string[]; deptPath: string; orgId: string; issuedAt: Date; }
export function hasDept(u: User): boolean;
export function userFrom(context: unknown): User | undefined;
export function requireUser(context: unknown): User;          // 抛 GraphQLError，extensions.http.status = 401
export function scopeFrom(context: unknown): ScopeFilter;     // 同上
export function hasPermission(context: unknown, key: PermKey): boolean;
// 弃用：scopeOf(context)
// 测试：import { withUser } from "besdk/testing"
```

**为什么保留 `ScopeOf` 的 panic 一版而不是立刻删**：2.0.x 组件在外壳里会被 MVS 抬到新 SDK（外壳钉成员中最高的版本），旧代码必须照常编译、照常行为。下一个 SDK minor（v0.8.0）删除，届时 gate 扫描残留调用。

### 6.4 各组件改动（议题四，与议题三同批，版本见 §5.4）

把下列调用点从 `ScopeOf(ctx).Owner` / recover 改成 `RequireUser` / `ScopeFrom`：authz `http.go:82`；iam `http.go:108`；workflow `service.go:150,182,195,204`；opportunity `service.go:64,90,265,325,342,352,363`；sales `service.go:31,158,166,178`、`tcc/create.go:49,98-107`；inventory `service.go:27-30`；finance `service.go:36-39`、`grpc.go:28-44`；notification `service.go:36,49,54`；print `routes.py:67`。测试里的 `besdk.ContextWithClaims` 换成 `besdktest.WithUser`。

### 6.5 先写的红测试

- Go `TestUserFrom_没有验签身份时返回false且不panic`、`TestRequireUser_没有身份返回codes_Unauthenticated`、`TestRequireUser_Gin错误映射成401`、`TestScopeFrom_没有身份返回Unauthenticated`、`TestHasPermission_bundle未就绪时为false`、`TestHasPermission_没有用户时为false`、`TestBesdktest_WithUser构造的ctx被UserFrom认出`。
- Python `test_current_user_没有身份返回None`、`test_require_user_没有身份抛Unauthenticated且映射401`、`test_contextvar_同时带身份与范围`。
- TS `userFrom 没有身份返回 undefined`、`requireUser 抛 401 的 GraphQLError`。
- be-acceptance `TestBesdktestImportScan_生产代码导入besdktest报错`。

---

## 7. 总落地顺序

**一期（不需要新决策，可以马上排）**

1. 三个 SDK v0.6.0 并行（各自仓库提交；tag / 推送留给控制者）：先写 §3.5、§5.5、§6.5 的 SDK 红测试 → 实现 → 文档（三份 `docs/authz-protocol.md` 同步）。
2. iam 2.0.1（`typ: access`）与 authz 2.1.0（§3.4）并行；authz 发布后改 `config/vars.yaml` 的 `AUTHZ_BUNDLE_URL`，`make gates`（`service-hostname-scan`）。
3. 组件补丁版本（§5.4 表，可按仓库并行）：每个先写本组件的红测试（inventory / opportunity / mdm 的 gRPC Unauthenticated、sales / opportunity 的快照取身份），升 SDK、改调用点、跑 C1–C6、`make verify`，走 `version-bump-ship`。
4. 文档：`02-backend.md` Permissions / Data scopes / Calling other components、`AGENTS.md` 易错点表两行、新决策 0208（gRPC 系统协议）；中英镜像，`make docs-mirror`、`make docs-boundary`。
5. 外壳 T22–T24：`go.mod` 钉 be-sdk-go v0.6.0；`serveExtraPort` 自带身份拦截器，外壳无需改代码。

**二期（等 0207 拍板）**

6. 0207 定稿 → authz 2.2.0 → SDK v0.7.0 → inventory / finance 2.1.0（取并集过渡）→ sales / opportunity / workflow / notification 2.1.0 → 种子改走 authz → 前端 1.1.0 范围说明（06c）。
7. 下一轮清理：SDK v0.8.0 删 `ScopeOf` / `UserClient` / `SystemClient` / `ContextWithClaims`；inventory / finance 删本地授权表（按 Q7 的结论定版本号）。

**版本汇总**

| 仓库 | 一期 | 二期 |
|---|---|---|
| be-sdk-go / python / ts | v0.6.0 | v0.7.0（v0.8.0 清理） |
| infra/iam-casdoor | 2.0.1 | — |
| infra/authz | 2.1.0 | 2.2.0 |
| erp/sales、crm/opportunity、erp/inventory、erp/finance、infra/notification | 2.0.1 | 2.1.0 |
| infra/workflow | 2.0.2 | 2.1.0 |
| mdm/customer | 2.0.2 | — |
| mdm/product、infra/print、infra/bff-mobile | 2.0.1 | — |
| integration/im-dingtalk | 不动（不调 `ScopeOf`、无用户 rpc） | — |
| be-acceptance | `perm-key-usage-scan`、`besdktest` 导入扫描、退役 `system-client-scan` | — |
| be-ops | — | `data-scopes.tsv` 加 `role` 列 |
| frontend/standard | — | 1.1.0 |

`sdk-redesign.md` 应把 §6 的 `User` / `ScopeFrom` / `HasPermission`、§5.3 的 `Dial` / `UserHTTP` / `SystemFrom`、§4.5 的 `ScopeFilter.Level` / `Values` 当作输入。

---

## 8. 需要你拍板的点

1. **0207（分配进 authz、档位挂在角色×键上）要不要做？** 这是本文最大的一项，改写 0205 的排除项。不做的退路是方案 A（各组件授权表规范化 + 补审计），"只能对自己的单子做"仍然不能表达。
2. **档位要不要 `dept`（只看本部门、不含下级）？** 若依有这一档。本文先只给 `own`/`subtree`/`all` 三档，因为 `dept` 需要组件加一条 `dept_path = @exact` 的 SQL 分支，没有它的组件不能宣称支持；需求出现再加。
3. **`/api/tenant/features` 的去留**：收窄成登录前需要的最少信息、把"装了哪些组件"并进要登录的 `/api/me/access`（推荐），还是只改文档承认它是公开的？
4. **首个管理员**：本地开发要求 `.env` 配 `BOOTSTRAP_ADMIN_SUB`（种子不再直接写库），还是保留种子第 ① 步直接写库？
5. **mdm 的 gRPC 写 rpc 收紧成 Unauthenticated**：会不会有种子脚本或别的组件在用（需要实现前 grep 一遍 `scripts/` 和各 client 包）？
6. **BFF 的 8 个 `infra.bff-mobile.*` 键**：保留作"移动端单独授权"（每个移动端用户都要两套键），还是 BFF 的 resolver 直接用下游的键、只留一个 `infra.bff-mobile.use` 作为渠道开关？
7. **inventory / finance 的授权表与管理端点**：没有生产数据，是否允许在 2.1.0 直接删（破例 0302 只增规则），还是过渡一版、3.0.0 再删？
8. **资源维度的唯一归属**：`warehouse` 只允许 inventory 是 owner、别的组件只能 `uses`——要不要在 `data-scopes.tsv` 加这一列并让 be-ops 校验？
9. **finance 的信用敞口**：`GET /credit-exposure/:customer_id` 是跨法人的汇总，只要 `erp.finance.view`。多法人时它要不要按 `legal_entity` 维拆分或限定？（单法人今天无害。）
10. **`org_id` 改名**：JWT 的 `org_id` 实为"默认法人/租户"，和 `org` 维（部门）撞名。要不要在 iam 下一个版本加 `tenant_id`、`org_id` 标弃用？（0203 允许新增身份 claim，前提是所有支持的 IAM 实现都能签。）
