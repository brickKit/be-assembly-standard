# infra-authz · 权限账房 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `infra/authz` |
| 仓库名 | `infra-authz` |
| 端口 | HTTP `8222` / gRPC `9222` ← 抄 `registry/ports.tsv` |
| schema / role | `infra_authz` / `infra_authz_rw`（归档 `infra_authz_archive`） |
| 语言 | Go |
| 框架栈 | Gin + `database/sql`+`pgx stdlib` + `sqlc` + `golang-migrate`（设计书 §12.4） |
| 合并部署时进 | 外壳三 `go-infra` |
| 装配角色 | `default` |
| 阶段 | 第三阶段（与 `infra-iam-casdoor`、`frontend-standard` 同期） |

> 规范源是设计书**第 14 章**。本文件只做该章在本组件上的落点与决策记录，冲突时以第 14 章为准。

## 1. 边界

**归我：**

- **权限键册**的宿主：`be-ops` 产出 9 经 `config.permissionCatalog` 灌进来，我 upsert 进表，供管理界面渲染。
- **角色模型**：`roles` / `role_permissions` / `user_roles`（后者带 `expires_at`）。纯并集，**无 Deny**。
- **策略下发**：`GET /authz/bundle`——`role → [permission keys]` 加一个有界的 `stale_since`。
- **登录期 claims 计算**：`iam` 适配层在发 token 前调我一次，拿 `roles[]` / `dept_path` / `org_id`。
- **前端两个查询口**：`GET /api/me/permissions`、角色管理的 CRUD。
- **阶段三的极简部门表**：只为给出 `dept_path`。⚠️ **临时的**，阶段五 `mdm-org` 上线后由它接管（见第 9 节）。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| 用户身份、密码、登录、OIDC 流 | Casdoor 官方镜像 + `infra-iam-casdoor` | 我只认 `sub`。这条切分让 `slot:iam` 换 Keycloak 时**角色数据一行都不用迁**（设计书 §6.12） |
| **单次鉴权判定** | 各组件的 `be-sdk`（进程内 map） | §14.1.4：我不在请求热路径上。做成中心 PDP 就是 Zanzibar，那条路对「客户本地一台电脑」不成立 |
| **数据权限规则** | 各组件的 `assembly.yaml` + 代码 | §14.2.1：数据权限随版本上线，不在我这里配 |
| 组织架构主数据（部门、岗位、汇报线） | `mdm-org`（阶段五） | 我只借用「部门路径」这一个字符串 |
| 菜单树 | 各组件 `assembly.yaml` 的 `menus`，`be-ops` 生成期聚合 | 决策 112：没有中心菜单表，这是骨架为什么是两级导航的原因（§12.6.7） |
| 审计日志 | `infra-audit` | 我发事件，它落库 |

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `permissions` | 不分区 | — | 权限键册镜像。几百行，恒小 |
| `roles` | 不分区 | — | 含专属角色 `u:<sub>`（「给某人单独加一个权限」的底层实现） |
| `role_permissions` | 不分区 | — | 角色 → 权限键。bundle 的主体 |
| `user_roles` | 不分区 | — | 用户 → 角色，带 `expires_at`。**唯一会随用户数增长的表**，但它不进 bundle |
| `role_changes` | `changed_at` | 月 | `stale_since` 的来源：谁在什么时候角色变了 / 被撤销了。**只读最近 2×TTL 的窗口**，其余可归档 |
| `departments` | 不分区 | — | ⚠️ **阶段三的临时表**，只为给出 `dept_path`。阶段五由 `mdm-org` 接管 |

强制字段全部符合 §11.2.1。**`data_scopes: none`** ——权限数据本身不做行级过滤，能进管理界面的人（`infra.authz.admin`）就能看全部；这是功能权限的事，不是数据权限的事。

**终态列表**：`user_roles` 的 `expired`、`role_changes` 的任意记录（写入即终态）。

## 3. 契约面

**gRPC（`infra.authz.v1.AuthzService`）：**

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `BatchGetRoles` | 读 | — | §3.8 强制的 `batchGet` |
| `ResolveClaims` | 读 | — | 给 `iam` 适配层：`sub` → `roles[]` / `dept_path` / `org_id`。**登录与刷新时各调一次** |
| `GetBundle` | 读 | — | gRPC 版的 bundle，给不方便走 HTTP 的调用方备用 |

**对外 REST 路径前缀：** `/infra/authz/**`

| 路径 | 权限键 | 说明 |
|---|---|---|
| `GET /authz/bundle` | `besdk.Public`（但仅内网可达，见下） | 策略下发。带 `ETag`，未变返 `304` |
| `GET /api/me/permissions` | 仅需登录 | 前端拉本人的 `page` + `action` 键集合 |
| `GET/POST/PUT/DELETE /api/admin/roles/**` | `infra.authz.admin` | 角色 CRUD、勾权限、给人授角色 |
| `POST /api/admin/users/{sub}/revoke` | `infra.authz.admin` | 踢人：撤 refresh token + 写 `role_changes` |

⚠️ **`/authz/bundle` 不进 `edge_routes`**——它只在内网被各组件拉取，不经网关暴露。`be-ops` 生成路由表时要跳过它。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `infra.authz.role.changed.v1` | 旁路 | 角色或其权限集变更 | `role_id`、变更类型。**仅供 `infra-audit` 落审计**——下发不走事件，走 bundle 轮询 |
| `infra.authz.user_role.changed.v1` | 旁路 | 给人加/减角色、到期、踢人 | `sub`、变更类型。同上，仅供审计 |

⚠️ **策略下发刻意不走事件总线。** 走事件就要求每个组件消费 + 落本地表 + 处理乱序与重放；而 bundle 轮询是**无状态的、幂等的、天然收敛的**——组件挂了重启拉一次就是最新（§14.1.4）。

**消费：**

| subject | 来自 | 做什么 | 幂等与乱序怎么处理 |
|---|---|---|---|
| `mdm.org.department.changed.v1` | `mdm-org`（**阶段五才有**） | 更新 `departments` 的 `dept_path` | 按 `version` 单调校验（§H） |

## 5. 依赖

**强依赖**（同步 gRPC，缺失时平台阻断启动）：无。

**弱依赖**（`optional: true`）：

| 组件 | 用途 | 缺失时降级成什么 |
|---|---|---|
| `mdm-org` | 组织树，给 `dept_path` | 阶段三本来就没有它：用自己的 `departments` 临时表 |

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| `infra-iam-casdoor` | **方向是反的**——是 `iam` 调我算 claims，不是我调它。我只认 `sub` 这个字符串。这条也是 `slot:iam` 可替换的物理前提（§5.11） |
| **所有业务组件** | ⭐ 反过来也一样：**62 个组件对我不声明依赖**，我的地址走各组件 `configSchema` 的 `authzBundleUrl`（同 §6.1 的 `iamJwksUrl` 先例）。61 条依赖边既没必要，也会把启动顺序绑死；而 §14.1.9 的 fail-static 让顺序无关紧要 |
| `infra-audit` | 走事件，不同步调 |

## 6. 在同步图与三枢纽里的位置

**不在同步图里**——没有任何组件对我建同步边，我也不对任何人建。我与 `iam` 之间是一条单向调用（`iam → authz`），发生在登录/刷新链路上，不在业务请求路径上。

因此**不可能引入环**，也与「CRM 与 ERP 零同步边」无关。与三枢纽（`mdm` 只读枢纽 / `inventory` 物理命令枢纽 / `finance` 事件汇）都没有关系——我是一条**旁路上的账房**。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `permissions` / `roles` / `role_permissions` | 永远热 | 不归档 | — |
| `user_roles` | 永远热 | 不归档（过期行保留，供审计追溯「他当时有什么权限」） | — |
| `role_changes` | 最近 2×TTL | 超过 7 天 | `infra_authz_archive` |

⚠️ **`role_changes` 只有最近 2×TTL 的窗口参与 `stale_since` 计算**——超过 TTL 的 token 本来就失效了，所以这个列表恒短（个位数到几十条）。这是「人的角色变更也能 ~15 秒生效」而 bundle 不膨胀的关键（§14.1.6）。

## 8. 参考实现

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Open Policy Agent | 📋 开工前填 | Bundle API（`ETag` 条件拉取、`fail-static` 降级、bundle 过期指标） | **本组件的下发形态整个来自它。** 尤其是「策略下发到本地、决策在内存」与「拉不到就用旧的继续跑」这两条 | Apache-2.0 | 借鉴逻辑 |
| Kubernetes RBAC | 📋 开工前填 | `rbac/v1` 的 Role / RoleBinding | **纯并集、无 Deny** 的立场与它的公开理由（可推理性） | Apache-2.0 | 借鉴逻辑 |
| Casbin | 📋 开工前填 | RBAC with domains 的模型定义 | 只看模型分层，**不引入它**——我们的模型比它简单得多，引进来是多一层间接 | Apache-2.0 | 借鉴逻辑 |
| Salesforce | — | Profile / Permission Set / Permission Set Group | 「基线 + 可叠加的权限集」这个分层；以及**它的 Sharing Table 重算代价**——那正是我们把数据权限放到版本里的直接理由 | 闭源 | 借鉴实际应用 |
| AWS IAM | — | 策略求值、最终一致性口径 | ⚠️ **反面**：Deny/Allow 的求值顺序不抄。正面：「策略变更几秒内生效」的口径给了我们 15 秒的底气 | 闭源 | 借鉴实际应用 |

**明确没有参考的**：Zanzibar / SpiceDB / OpenFGA 的关系元组模型。**不是没查，是查过后判定不适用**——它解决的是「每条资源有自己的 ACL」（文档共享），而 ERP 的可见性是「按组织结构成片划分」，用关系元组表达等于给每条单据存一行 ACL。而且它的性能靠的是几万台机器（§14.1.4）。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| SAP | 把功能权限与数据权限塞进同一个 Authorization Object | 两者的变更频率差两个数量级（每天 vs 制度级）。合在一起之后每加一个部门都要动权限模型（决策 115） |
| 传统中台 | 权限键全塞进 JWT | 管理员的全集顶爆 8KB header，**症状是登录成功、随后所有请求 431**（§14.1.5） |
| Odoo | `ir.rule` 用 domain 表达式，ORM 每次查询注入 | 我们零 ORM（§12.4 锁 `sqlc`），没有那个注入点；而且表达式是运行时求值的字符串，AI 读不懂也测不了 |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

**无。** 核过 §5.11.1 的判据：五档数据范围（全部/本部门及下级/本部门/本人/自定义）在各家成熟 ERP 高度一致，不存在「多种都合理、只服务不同客户画像」的分歧；分歧在「用哪几个维度」，那是 `assembly.yaml` 的声明式配置，对应判据表里「单据编号规则」那一行。**不新增槽位族。**

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | `departments` 临时表迁到 `mdm-org` 的 runbook：两份部门数据共存期怎么切、`dept_path` 怎么对齐 | 阶段五 `mdm-org` 开工前 | 📋 |
| 2 | bundle 的实测大小与拉取耗时（预估几十 KB，需实测；超过 1MB 就要考虑按组件前缀切片下发） | 阶段三首个真实客户角色集就位后 | 📋 |
| 3 | `access token` TTL 的最终取值（初值 10 分钟）。它决定 `stale_since` 窗口大小与 refresh QPS | 阶段三压测后 | 📋 |
| 4 | 字段级权限（`type: field`）的 DTO 掩码在 `be-sdk-go` 里怎么实现——反射 / 代码生成 / 手写 | 阶段三写 `hrm-payroll-es` 或 `erp-finance` 时 | 📋 |
| 5 | `role_changes` 与 `infra-audit` 的职责是否重叠（我保留 7 天窗口，它长期存） | 阶段五 `infra-audit` 开工时 | 📋 |
