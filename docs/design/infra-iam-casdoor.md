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
- **claims 镜像同步**：把 `infra-authz` 的 `roles[]`/`dept_path`/`org_id` 写进 Casdoor 的用户属性，**让 Casdoor 自己签出带角色的 token**（§3.2 是这条的全部理由）。
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
| `claim_sync_state` | 不分区 | — | `sub` → 已同步的 claims 指纹 + `authz_revision` + `synced_at`。**§3.2 那条顺序保证的落点**，恒小（按用户数） |
| `webhook_deliveries` | `received_at` | 月 | Casdoor webhook 的投递去重（它会重投）。只留最近窗口，其余归档 |
| `bootstrap_state` | 不分区 | — | 首次初始化的幂等标记：哪一步做过了。单行到个位数行 |
| `event_outbox` / `event_inbox` | `created_at` | 周 | 标准两张（§3.10、§11.2.5） |

强制字段全部符合 §11.2.1。

**终态列表**：`webhook_deliveries` 写入即终态；`claim_sync_state` 无终态（长期存活的当前态镜像）。

⚠️ **本组件不存用户表。** 用户主数据在 Casdoor 里，我只存"我给它同步过什么"。想查用户属性走 §3 的 `BatchGetUsers`（回源 Casdoor），**不许在这里建一张 users 影子表**——那等于把 `slot:iam` 的可替换性又焊死一次。

## 3. 契约面

**gRPC（`infra.iam.v1.IamService`）：**

⚠️ **包名是 `infra.iam`，不是 `infra.iam_casdoor`。** §5.11 要求**族内契约面完全一致**——`infra-iam-keycloak` 将来要原样实现这一份契约，调用方不该因为换了实现就改 import 路径。事件名同理（§4）。

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `BatchGetUsers` | 读 | — | §3.8 强制的 `batchGet`：`sub[]` → `display_name`/`email`/`phone`/`im_accounts`。**回源 Casdoor，不落本地表** |
| `GetTenantFeatures` | 读 | — | gRPC 版的 features 清单，给 BFF 用 |
| `SyncClaims` | 命令 | `sub` + `authz_revision` | 给 `infra-authz` 兜底重放用的对账入口（正常路径走事件，见 §4） |

**对外 REST 路径前缀：** `/infra/iam/**`（同样是**族级**前缀，不带 casdoor）

| 路径 | 权限键 | 说明 |
|---|---|---|
| `GET /api/tenant/features` | `besdk.Public` | 前端启动时拉。**Public 是刻意的**：还没登录就要用它决定渲染什么 |
| `POST /api/iam/webhooks/casdoor` | `besdk.Public` + 签名校验 | Casdoor 回调。**Public 指的是"不走权限键"，不是"不校验"**——用 Casdoor 的 webhook 签名验，这条必须在 `AGENTS.md` 里写死 |

⚠️ **登录、登出、刷新 token 三条路径都不在这张表里**，它们是浏览器 ↔ Casdoor 的标准 OIDC 流，本组件既不代理也不转发（§6.1）。

### 3.1 `/api/tenant/features` 的数据从哪来

平台不给任何组件"当前装配了什么"的视图，所以只能从外面喂（§6.1）：`be-ops` 生成 `brickkit.yaml` 时把启用清单写进本组件的 `config.enabledComponents`，我读环境变量 `ENABLED_COMPONENTS` 原样下发。

⚠️ **必须是逗号分隔字符串，不能写 YAML 数组**——数组会被平台渲染成 `[a b c]`（导读第 7 条、阶段二平台断言用例 7 已经真机验过）。⚠️ 平台**不校验值**，喂错内容不会有任何运行时失败，只会让前端少几个菜单，所以**校验是 `be-ops` 自己的责任**。

### 3.2 ⭐ 角色怎么进 JWT：镜像同步 + 一条顺序保证

**这是本组件唯一有设计难度的地方。** 两个约束互相顶：

| 约束 | 出处 | 说的是 |
|---|---|---|
| 登录流不经过适配层 | §6.1 | 浏览器直连 Casdoor 走标准 OIDC，我不在中间 |
| JWT 必须带 `roles[]`/`dept_path`/`org_id` | §14.1.5 | 而这些数据在 `infra-authz` 里，不在 Casdoor 里 |

**只有一条路同时满足两者：把 claims 提前镜像进 Casdoor，让 Casdoor 用自己的签名密钥签出带角色的 token。** 本组件负责这次镜像。

**但朴素做法会造出一个真实的死循环**，必须在设计阶段就堵掉：

```
authz 改了张三的角色
  → bundle 的 stale_since[张三] = now        ← §14.1.6
  → 组件看到张三的 token 早于 stale_since，返回 401 token_stale
  → 前端静默刷新 → 找 Casdoor 换新 token
  → ⚠️ 如果这时候镜像还没同步到 Casdoor，换回来的还是旧角色
  → 再次 401 token_stale → 再刷新 → 死循环，且用户侧表现为"页面转圈转不完"
```

**解法是把 `stale_since` 的写入时机往后挪一格**——不是 authz 改完就写，而是等镜像落地确认：

```
authz 改角色 → 发 infra.authz.user_role.changed.v1
  → 本组件消费，把新 claims 写进 Casdoor（幂等，带 authz_revision）
  → 本组件发 infra.iam.claims.synced.v1
  → authz 消费它，这时才把张三写进 stale_since
```

于是**任何组件看到 `stale_since[张三]` 的那一刻，Casdoor 一定已经能签出新角色**，循环不可能发生。代价是多一跳事件（毫秒级），而生效时延的大头本来就是 bundle 的 15 秒轮询（§14.1.6），**总时延不变**。

⚠️ **这条要求 `infra-authz` 消费 `infra.iam.claims.synced.v1`**，与它设计计划 §4 现在写的"策略下发刻意不走事件总线"不冲突——那句说的是 **bundle 内容**不走事件；这里走事件的是**一次同步完成的确认信号**，不是策略本身。已在 `infra-authz` 设计计划 §4 补了这条消费边。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `infra.iam.user.created.v1` | 核心 | Casdoor webhook 报告新用户 | `sub`、`display_name`、`email`、`phone`、`im_accounts`（含钉钉 unionid，若已绑定） |
| `infra.iam.user.updated.v1` | 核心 | 用户属性变更 | 同上 + `version` 单调递增 |
| `infra.iam.user.disabled.v1` | 核心 | 停用/删除 | `sub`。⚠️ **删除也发这条，不发 deleted** ——下游要的是"别再给他发消息了"，不是"把历史记录删了" |
| `infra.iam.claims.synced.v1` | 核心 | claims 已写进 Casdoor | `sub`、`authz_revision`。**§3.2 那条顺序保证的信号**，唯一消费者是 `infra-authz` |
| `infra.iam.login.v1` | 旁路 | 登录成功 | `sub`、时间、IP。仅供 `infra-audit`（阶段五）落审计 |

⚠️ **`user.*` 三条标核心不标旁路**：`infra-notification` 靠它们维护"给谁发、发到哪"的快照（见 §5），漏一条的后果是**审批通知发不出去且没有报错**——那不是分析类事件能接受的可靠性。

**消费：**

| subject | 来自 | 做什么 | 幂等与乱序怎么处理 |
|---|---|---|---|
| `infra.authz.user_role.changed.v1` | `infra-authz` | 把新 claims 镜像进 Casdoor（§3.2） | 幂等键 `sub + authz_revision`；**乱序靠 `authz_revision` 单调比较**，收到比已同步的更旧的直接丢弃 |

## 5. 依赖

**强依赖**（同步 gRPC，缺失时平台阻断启动）：

| 组件 | 调它的什么 | 为什么必须同步 |
|---|---|---|
| `infra-authz` | `ResolveClaims`（首次初始化、以及事件丢失后的对账重放） | 正常路径走事件；但**冷启动时没有事件可听**——第一次部署要把已有用户的 claims 全量刷进 Casdoor，只能同步拉。这条边的方向与 `infra-authz` 设计计划 §5 记的完全一致（"是 iam 调我"） |

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
| `claim_sync_state` | 永远热 | 不归档（用户停用后也留着，供审计追溯"他当时被同步过什么"） | — |
| `bootstrap_state` | 永远热 | 不归档 | — |
| `webhook_deliveries` | 最近 30 天 | 超过 30 天的整月分区 | `infra_iam_casdoor_archive` |
| `event_outbox` / `event_inbox` | 已发布 30 天内 | 超过 30 天 | 清理（§11.7 全组件通则） |

⚠️ **`claim_sync_state` 永不归档也永不分区**：它是按用户数有界的当前态镜像（几百到几千行），分区只会让 §3.2 的幂等查询变慢。

## 8. 参考实现

> 完整调研过程见 [`_调研记录/03-阶段三.md`](./_调研记录/03-阶段三.md) 的「infra-iam-casdoor：适配层与 claims 镜像」一节。下表是精炼版。
> ⚠️ 那份记录把每条都标了 🧭（架构推理，不依赖外部源码）或 🔍（依赖外部项目实际行为，**开工前必须核对**）——
> 本表第一行 Casdoor 那条的关键细节属于 🔍，见 §9 第 1 条。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Casdoor | 📋 开工前填 | `object/token_jwt.go`（token 里带哪些字段）、`object/user.go` 的 `Properties`、webhook 触发点 | **本组件全部的对接面。** 尤其要确认：自定义 claims 到底是走 `User.Properties` 还是 Casdoor 的角色对象——这决定 §3.2 镜像同步写哪个字段（§9 第 1 条） | Apache-2.0 | 借鉴逻辑 |
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
| 1 | Casdoor 的自定义 claims 到底写哪里——`User.Properties`、原生 role 对象、还是 application 级的 token 字段配置？这决定 §3.2 镜像同步的具体写法 | 开工前读 Casdoor 源码（§8 第一行）时 | 📋 |
| 2 | Casdoor 的 webhook 有没有投递保证与签名机制？没有的话 `webhook_deliveries` 的去重键取什么、要不要改成轮询兜底 | 同上 | 📋 |
| 3 | 钉钉 unionid 从哪来：Casdoor 的 DingTalk 第三方登录会把 unionid 存进用户属性吗？拿不到的话 `infra-notification` 就得靠人工维护映射（会牵连它的设计） | 阶段三 Task 7 实现时，与 `integration-im-dingtalk` 一起验 | 📋 |
| 4 | `infra-iam-keycloak` 什么时候建？族内契约一致要求它能原样实现 §3 那份 proto，但阶段三只建 Casdoor 一个——**契约设计得对不对，要到真建第二个成员时才验得到** | 阶段六（按客户订单排队，§9.6 档 4b） | 📋 现在的对策：§3 的契约按 Casdoor/Keycloak 两边能力的**最小交集**设计，并在 `AGENTS.md` 记一条"加 rpc 前先问 Keycloak 能不能实现" |
| 5 | 首次初始化要不要做成幂等的"每次启动都对账"，还是只跑一次？前者更安全但每次启动多几个 Casdoor API 调用 | 开工实现时 | 📋 倾向前者（`bootstrap_state` 逐步记录、每步幂等），理由同 `erp-inventory` 的 claim-first：单机测试测不出"跑了一半挂了"的中间态 |
