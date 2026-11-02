# 授权架构：需求模型、授权契约、列表过滤、槽位族与一致性测试——设计提案

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准（be-sdk-* 均在 v0.5.0；组件在 `brickkit.yaml` 所列的 2.0.x）。
> 建在 `identity-permissions.md`（下称"上一份"）之上：那里已经论证过的（功能权限 8 个缺口、`typ` 漏洞、gRPC 是系统协议、`User`/`RequireUser`、档位 + 维度取值进 bundle）这里只引用、不重复。本文回答的是用户 2026-10-02 的新要求：**共享迟早要做、按终局设计、做成可替换的槽位族、带一致性测试套件**。
> 为确认"槽位族成员不能被依赖"的平台规则，读过 brickKit 源码仓库 `docs/en/09-patterns/01-component-design.md:110-123`（知识缺口记录：本项目文档里没有这条规则的原文，只有 0104 的结论）。

---

## 0. 结论（一页）

1. **需求分 8 类，外加 2 类明确"不归授权"**（§2）。8 类是：功能权限、按档位和维度的数据范围、记录共享、关系派生的访问、委托 / 代办 / 代理人（含 AI agent 降权 token）、字段级权限、限时访问、审计与解释。不归授权的是业务不变量（"草稿才能改"）和职责分离（"建单人不能审自己的单"），它们留在组件代码里。可见性只有一个组合公式：**可见 = (规则分支：档位 × 各资源维度) ∪ 共享 ∪ 关系派生**。在一个主体内部仍是纯并集（0204）；只有沿委托链（代理人、代办、扮演）才取交集，相当于 AWS 的 permission boundary，不是 Deny 规则。
2. **授权契约分两层**（§3）。
   - **provider 契约 `infra.authz.v2`**：authz 槽位的每个成员都实现它，内容是身份 claims、本地 bundle、关系元组写入与 changefeed、远程 Check / BatchCheck / ListObjects、Explain、Admin、能力声明。
   - **资源契约**：SDK 在每个业务组件里自动挂出 `/{domain}/{name}/_authz/check|explain` 和 `/_shares`。原因是"按规则能不能看这一行"只有拥有这行数据的组件知道（行上的 `owner_id`、`dept_path`、`warehouse_id`），authz 只知道"谁被显式授予了什么"。两层合起来，任何模型都能放在后面：RBAC + 档位、ReBAC、静态文件，以及只用于动作判定的 ABAC。
3. **列表过滤用混合方案 (c)，默认走本地投影 (b)**（§3.5）。authz 只把**直接元组**（共享、成员关系）以 changefeed 下发；SDK 在组件自己的 schema 里维护 `besdk_authz_acl` 投影表，主体一侧的展开（我是谁、我的角色、我的部门及其祖先、谁委托了我）在查询时从 token 和 bundle 现算。列表 SQL 是一条**规范谓词**：规则分支 OR `EXISTS(acl)` OR `id = ANY(图类型 ids)`，仍是静态参数化 SQL，没有 RLS。远程 `ListObjects` 只给声明了 `derivation: graph`、并且 provider 声明了 `graph` 能力的类型用，且有上限。这样做的结果：0202 的"热路径不跨网络"、principle 1 的"单独能跑"、外壳"只合并进程"三条都成立；也避开了 Salesforce 那种派生共享物化后的重算风暴，因为投影里没有派生数据。
4. **一致性令牌**：provider 的 `revision` 是单调 int64，以字符串传输。写共享时返回它；请求可以带 `X-Authz-Revision`。投影水位不够时，SDK 先同步追平；追不上时，单条读回落到远程 Check，列表在响应头标 `X-Authz-Consistency: stale`。对应 Zanzibar 的 zookie、SpiceDB 的 ZedToken `at_least_as_fresh`、OpenFGA 的 `HIGHER_CONSISTENCY`。
5. **能力协商写进 bundle**：`capabilities` 分 core 和可选两组。core 是功能键、档位、维度取值、字段键、stale、revision、claims、目录同步、`me/access`；可选的是 `admin_write`、`sharing`、`relation_sync`、`check`、`graph`、`delegation`、`agents`、`impersonation`、`access_review`、`explain_paths`、`conditions`。缺一项能力时 SDK 明确降级：共享端点答 `501 capability_unavailable`，投影为空，前端隐藏入口。组件可以在 `assembly.yaml` 写 `requires_capabilities`，be-ops 在组装期校验。
6. **槽位族，按这个顺序建**（§5）。
   - ① `infra/authz`（原生 PG，默认成员，全量能力，图能力只到一跳）。
   - ② `infra/authz-static`（文件配置，没有库，没有共享）：它最便宜，也最能证明"可替换 + 显式降级"。
   - ③ `infra/authz-openfga`（ReBAC 适配器，OpenFGA 按 0106 算基础设施），在 `prj/project` 出现、或者需要证明图模型时再建。
   - ④ `authz-cedar` / OPA：只有真实 ABAC 需求时才建，而且条件只用于动作判定，不用于可见性，否则列表和单条判定会不一致。
   
   先决条件：去掉 `infra/iam-casdoor → infra/authz@2.0.1` 这条依赖边（`components/infra/iam-casdoor/component.yaml:26`）。整个 authz 族只经共享变量 `AUTHZ_URL` 访问（0107 的推广），否则按 0104 (b) 它不能成为槽位。
7. **一致性测试套件放在 be-acceptance**，分三层（§5.4）。
   - 决策向量：一组 JSON 黄金用例，三门 SDK 必须算出相同结果。
   - provider 黑盒：按能力分组；没声明的能力，断言它确实明确降级。
   - 端到端：一个夹具组件，用真 SDK 跑在每个成员上，断言"列表里出现 ⇔ `Can` 为真"，即 List/Can 一致性。
8. **对现有组件**（§6）：
   - inventory、finance 删掉本地授权表。
   - sales、opportunity、workflow、notification 换成规范谓词与档位，`.admin` 键退役。
   - sales、opportunity 声明可共享类型。
   - product 成本、销售价格、客户额度声明字段键。
   - R62 细化成"看不见就一律 404，看得见做不了才 403"（待拍板 Q3）。
   - 决策：0205、0206 原地重写；0207（分配在 authz）、0208（gRPC 系统协议）照上一份起草；新增 0209（authz 槽位族与契约）、0210（委托与代理人）、0211（字段级权限）；修订 0101、0104、0107、0202、0203、0204。
9. **落地**（§7）：分 P0–P3。**P0 在组外壳之前做完**：契约形状一次定全，SDK 的 Access API 和规范谓词（acl 分支先留着，投影为空），去掉 iam→authz 依赖边，档位和维度取值，删本地授权表，core 一致性测试。共享端到端、字段掩码、Explain、static 成员随 06c（P1）；委托、审计（P2）；agent、openfga（P3）都是只增的，不破契约。

---

## 1. 现状与上一份的位置

| 已有 | 证据 |
|---|---|
| 纯并集 RBAC，本地 bundle，15 秒条件轮询，fail-static | `tools/be-sdk-go/bundle.go:329`、`:402-405`；`components/infra/authz/backend/internal/repo/bundle.go:14-17` |
| 路由注册强制带键；判定链是"验签 → stale → 查键" | `tools/be-sdk-go/authz.go:37-55`、`:137-194` |
| 进程级全局 authz 运行时；外壳里只装一份 | `authz.go:63-66`；`shell.go:58-74`（`InitShellAuthz`） |
| `ScopeFilter{All,HasDept,Prefix,Exact,Owner,In}`，`In` 从不填，取不到就 panic | `tools/be-sdk-go/scope.go:266-277`、`:293-300` |
| 角色到期 `user_roles.expires_at`，是现有唯一的"限时"能力 | `components/infra/authz/migrations/001_create_authz.up.sql:39-49` |
| 部门表是 authz 里的临时表，等 mdm/org 接管 | 同上 `:51-61`；`registry/ports.tsv:6`（mdm/org 已登记端口） |
| inventory、finance 自建授权表和管理 API | `components/erp/inventory/migrations/004_create_warehouse_access.up.sql:1-20`、`backend/internal/http/http.go:36-38`；`components/erp/finance/backend/internal/http/http.go:40-42` |
| sales 列表是两个互斥视图（mine：owner；dept：前缀），写路径单独 `checkOrderInScope` | `components/erp/sales/backend/internal/repo/order.go:203-213`；`service/service.go:18-35` |
| `.admin` 键扩大范围 | `components/infra/workflow/backend/internal/http/http.go:32`；`components/infra/notification/backend/internal/http/http.go:25` |
| R62：范围外单条读答 404，命令答 403 | `dev/test-records/06b/erp-sales.md:193`；`dev/test-records/06b/infra-workflow.md:334` |
| iam 签 token 时同步调 authz `ResolveClaims`，是一条依赖边 | `components/infra/iam-casdoor/component.yaml:26`；`backend/internal/service/service.go:232` |
| bundle 端点是 `Public`，靠不进 `edge_routes` 来不对外 | `components/infra/authz/backend/internal/http/http.go:30`；`assembly.yaml:6-11` |
| 敏感字段直接下发：产品标准成本、订单单价 / 折扣、客户额度 | `components/mdm/product/contracts/product.openapi.yaml:167`；`components/erp/sales/contracts/*.openapi.yaml:229-232`；`components/mdm/customer/contracts/*.openapi.yaml:217` |
| 已登记、将来会提出共享和关系需求的组件 | `registry/ports.tsv`：`crm/customer`:13、`prj/project`:21、`infra/attachment`:33、`infra/audit`:35、`ana/ai`:57 |

**上一份的结论在本文里的位置**：

| 上一份 | 本文 |
|---|---|
| 档位 `own/subtree/all` 挂在（角色 × 键）上，资源维度取值挂在角色上，随 bundle 下发（0207 草案） | 保留，成为 provider 契约 core 的一部分；档位加 `dept`（I2 改判）；`org` 维也能挂取值（若依"自定义部门"） |
| 0206"没有共享引擎"不动 | **推翻**：共享引擎只有一个（在 authz），由 SDK 投影进组件，组件不手写共享表 |
| 0202"不要 SpiceDB / OpenFGA" | **修订**：可以作为槽位成员放在契约后面；热路径仍然不跨网络 |
| gRPC 是系统协议（0208 草案）、`User`/`RequireUser`/`ScopeFrom` | 保留。`ScopeFrom` 升级成 `Access`（§4.1） |
| `/api/me/access` | 保留并扩展：加能力、字段、委托、revision |

---

## 2. 需求模型

### 2.1 十类需求（8 类归授权，2 类不归）

| # | 类别 | 定义 | 本项目的具体例子 | 主流系统怎么做 |
|---|---|---|---|---|
| R1 | **功能权限** | 能不能调这个动作，与是哪一条记录无关 | `erp.sales.confirm`、`erp.finance.close`、菜单 `erp.inventory.view` | 若依菜单 / 按钮权限；Dynamics privilege；Salesforce object permission + permission set；ERPNext Role Permission Manager |
| R2 | **数据范围：档位 × 维度** | 同一个动作能作用于哪些行，由规则 + 分配决定 | ① sales"能看本部门及下级、只能取消自己的"：`view@subtree`、`cancel@own`。② inventory 仓管"查看南北两仓、只能调整南仓"：`view` 的 warehouse 值是 [S,N]，`adjust` 是 [S]。③ finance 按法人。④ workflow 按被指派人 + 部门。⑤ 若依"自定义部门"：华东大区经理看 /1/3/ 和 /1/7/ 两棵子树 | 若依 data_scope 五档 + `sys_role_dept`；Dynamics privilege depth（User/BU/Parent:Child BU/Org）；SAP 授权对象的组织字段；ERPNext User Permissions（按 Company / Warehouse 这类 Link 字段值限定，正是本项目的资源维度）；Odoo record rules（组内 OR、全局 AND） |
| R3 | **记录共享（显式授予）** | 把**这一条**记录以某个关系（viewer / editor）给某个主体（人、角色、部门、部门子树），可以带期限 | ① 销售把订单 SO-1001 只读共享给另一个大区的财务 BP。② 商机共享给售前工程师（editor），7 天。③ 客户档案共享给新接手的销售（将来的 `crm/customer`） | Salesforce manual sharing、Apex managed sharing（`__Share` 表 + RowCause）；Dynamics Share（PrincipalObjectAccess）；ERPNext DocShare（read/write/share/submit、everyone）；Odoo 分享向导、portal；Google Drive（Zanzibar） |
| R4 | **关系派生的访问** | 不是逐条授予，而是因为某个关系成立而可见 | ① **成员关系**：商机团队成员能看、能编辑商机（Dynamics access team、Salesforce opportunity team）；`prj/project` 的成员能看项目下的工时和任务（"项目成员可见"）。② **层级**：部门子树（已有）；汇报线上级看下属的单（将来 mdm/org）。③ **所有权链 / 父子**：附件（`infra/attachment`）跟随它挂的订单；订单行跟随订单；审批待办的处理人在待办打开期间能看被审批的单据。④ **任务派生**：被指派处理某张单的人临时可见（ERPNext `_assign`、Odoo followers） | Zanzibar userset rewrite（`computed_userset`、`tuple_to_userset`）；OpenFGA / SpiceDB 的 relation 定义；Salesforce implicit sharing（父子）、role hierarchy；Dynamics hierarchy security、access team template |
| R5 | **委托 / 代办 / 扮演 / 代理人** | 一个主体代表另一个主体行事，权限不超过被代表者，可撤销，有审计链 | ① **代办**：审批人 A 休假，把 10-01 到 10-07 的 `infra.workflow.task.act` 委托给 B，B 以自己的身份处理 A 的待办。② **扮演**：管理员以张三的身份只读查看（客服排障），全程留痕。③ **AI agent**（`ana/ai`）：用户授权"销售助理 agent"读订单、起草报价，但不能确认、不能共享、不能关账，1 小时有效，用户被撤角色后 agent 立刻同时失权。④ 服务账号：集成任务以 `svc:edi` 身份带有限角色运行 | OAuth 2.0 Token Exchange（RFC 8693，`act` claim 表示"谁在代表谁"）；RFC 9396 RAR；MCP 授权规范基于 OAuth 2.1；AWS session policy / permission boundary（有效权限 = 交集）；SAP / Dynamics 的代理审批（substitution） |
| R6 | **字段级权限** | 行看得见，某些列隐藏、打码或只读 | `mdm.product` 的 `standard_cost`；sales 的 `unit_price`、`discount` 和汇总金额；`mdm.customer` 的 `credit_limit`；将来 hrm 的薪资 | Salesforce FLS（profile / permission set）；Dynamics column security profile（默认隐藏，按 profile 放开）；Odoo 字段 `groups=`；ERPNext permlevel |
| R7 | **限时访问** | 任何授予都可以有起止时间，到点自动失效，不需要有人去撤 | 角色到期（已有）；共享 7 天；代办按日期段；agent token 1 小时；紧急提权（break-glass，2 小时，必须填理由） | Salesforce 临时访问；Dynamics 无原生、靠流程；OpenFGA conditions（CEL 时间条件）；SpiceDB caveats / expiring relationships |
| R8 | **审计与解释** | ① 每一次授予变更有事件、有 actor（含委托链）。② "为什么我能 / 不能"有唯一答案。③ 访问评审："谁能关账""谁能看到这张单" | ① 上一份 §3.3(a)：事件声明了却从没发过。② 页面上的"为什么看不到"横幅。③ 季度访问评审 | OPA decision log；Zanzibar Expand；OpenFGA ListUsers；Salesforce "Why can this user see this record"；Dynamics "Check access" |
| N1 | 业务不变量（不归授权） | 状态相关的规则 | "只有草稿能改价""已关账期间不能过账" | 所有系统都放在业务代码里；Cedar 可以表达，但放进策略后，业务规则就有了两个家 |
| N2 | 职责分离（不归授权） | 同一个人不能同时做两步 | 建单人不能审批自己的单；过账人不能复核自己的凭证 | 写成纯并集下的 Deny 会破坏 0204 的唯一解释；它是业务规则（workflow 的"处理人 ≠ 发起人"），组件代码检查，必要时由 workflow 强制 |

### 2.2 组合规则（唯一公式）

对一个主体 P、一个键 K、一行 r：

```
可见(P, K, r) =
      [ 规则分支(P, K, r)          -- R2：档位 × 维度（多个资源维度之间 AND，owner/org 两维之间 OR）
          ∧ 每个资源维度 d: r.d ∈ 取值(P, K, d) ]
   ∨  共享(P, r)  ⊇ 关系(K)         -- R3：直接元组，主体可以是 user / role / dept / dept_tree
   ∨  派生(P, r)  ⊇ 关系(K)         -- R4：一跳派生在投影里；多跳派生只用于 graph 类型
有效(P) = P 自身的并集  ∩  委托链上每一环的天花板（profile）      -- R5
字段(P, K, r) = 可见(P, K, r) ∧ 持有字段键                        -- R6
所有授予都带 [valid_from, valid_until)，在读取时判定                 -- R7
```

两条性质，写进一致性测试：

- **只增性**：共享和派生只会让可见范围变大，不会让它变小。纯并集在主体内部保持不变，"为什么能看"有唯一的来源列表。交集只出现在委托链上；解释的写法是"因为角色 X 授予了 K，且你的代理 profile Y 允许 K"，仍然唯一。
- **List/Can 一致**：对任何 P、K（读类键）和 r，`r ∈ List(P, K)` 当且仅当 `Can(P, K, r).Visible`。今天 sales 的列表和 `checkOrderInScope` 是两份代码（`order.go:203-213` 与 `service.go:24-35`）；有了共享以后，二者漂移是最常见的越权来源。

### 2.3 需求 × 参考系统覆盖面

对照的标准是"不比主流开源弱"：

| | 若依 | ERPNext | Odoo | Salesforce | Dynamics | Zanzibar / OpenFGA / SpiceDB | Cedar / OPA | **本设计** |
|---|---|---|---|---|---|---|---|---|
| R1 功能 | ✔ | ✔ | ✔ | ✔ | ✔ | 用关系表达 | ✔ | ✔（已有） |
| R2 档位 | 五档 | 部分（User Permission + "if owner"） | domain | OWD + 层级 | 四档 | 用关系表达 | 用策略表达 | **own/dept/subtree/all + 自定义部门 + 资源维度，按键求值** |
| R3 共享 | ✘ | ✔ | ✔ | ✔ | ✔ | ✔ | 模板策略 | ✔（authz 一处，组件投影） |
| R4 派生 | ✘ | 弱 | followers | 团队 / 层级 / 隐式 | access team / 层级 | **最强** | 属性 | 一跳在投影里；多跳交给 openfga 成员 |
| R5 委托 / 代理 | ✘ | ✘ | ✘ | 登录为 | 代理 | 原生没有 | ✘ | ✔（act / ceil / 交集） |
| R6 字段 | ✘ | permlevel | groups | FLS | 列安全 | ✘ | 可以 | ✔（字段键） |
| R7 限时 | ✘ | ✘ | ✘ | 部分 | ✘ | caveat / 条件 | 条件 | ✔（所有授予） |
| R8 解释 / 评审 | ✘ | 部分 | ✘ | ✔ | ✔ | Expand / ListUsers | decision log | ✔（两层 Explain + 访问评审） |

---

## 3. 授权契约

### 3.1 两层契约

```
            ┌─────────────────── provider 契约 infra.authz.v2（槽位族每个成员实现） ───────────────────┐
            │ ResolveClaims │ Bundle(+capabilities) │ Changes/ReadTuples │ WriteTuples │ Check/BatchCheck │
            │ ListObjects(graph) │ Explain │ Delegations │ Admin REST │ /api/me/access │ 事件              │
            └───────────────▲───────────────────────────────▲─────────────────────────▲──────────────────┘
                 iam（签 token 时）              每个组件的 SDK（轮询 / 拉取 / 写）      前端管理页（经网关）
                                                                │
            ┌──────────── 资源契约（SDK 在每个声明了 resources 的组件里自动挂出） ────────────┐
            │ POST /{d}/{n}/_authz/check    GET /{d}/{n}/_authz/explain                        │
            │ GET|POST|DELETE /{d}/{n}/_shares/{type}/{id}                                    │
            └─────────────────────────────────────────────────────────────────────────────────┘
                 前端（行按钮、共享对话框、"为什么"）、其他组件（附件、待办问父记录）、BFF
```

**为什么一定是两层**：规则分支依赖行上的属性（`owner_id`、`dept_path`、`warehouse_id`），这些属性只在拥有这行数据的组件里。

- Zanzibar 式的做法是"应用把每一行的属主、部门都写成元组"：每建一张订单就写 2–3 条元组，存在双写一致性问题，authz 成为每一个业务写入的同步依赖。这和 0101、0102、principle 1 都冲突。
- 本设计让**属性留在属主组件**、**显式关系进 authz**。属主组件是"这一行规则上能不能看"的决策点，authz 是"谁被显式授予了什么"的决策点。SDK 把两者合成一个决策。

对 openfga 成员，保留一个扩展点：属主组件可以把属性作为**上下文元组**随 Check 一起发过去（OpenFGA contextual tuples），由 provider 做整体判定。这只用于 graph 类型。

### 3.2 身份与 claims

0203 不变：token 里一个权限键都不放。claims v2 只增：

| claim | 含义 | 今天 | 来源 |
|---|---|---|---|
| `sub` `iat` `exp` | 主体（被代表者） | 有 | iam |
| `typ` | `access` / `refresh`；SDK 拒收 refresh | 只有 refresh 带 | iam（上一份 §3.3e） |
| `roles[]` | 角色码 | 有 | authz `ResolveClaims` |
| `dept_path` | 部门物化路径 | 有 | authz（将来 mdm/org） |
| `tenant_id` | 租户 / 默认法人（`org_id` 标弃用，I10） | `org_id` | authz |
| `act` | `{sub, kind: user\|agent\|svc}`，实际操作者；可以嵌套成链（RFC 8693 §4.1） | 无 | iam token exchange |
| `ceil[]` | 天花板 profile 码（和角色码同性质，是 bundle 里的引用，不是键） | 无 | iam 向 authz 建委托后填入 |
| `dg` | 委托授予 id，用来撤销 | 无 | 同上 |
| `azp` | 客户端（前端 / 移动端 / agent 宿主） | 无 | iam |

`ceil` 和 `roles` 一样只放码，码到键的映射在 bundle 里，所以不会撑大 token（0203 的 431 教训）。

服务账号是 `sub: svc:<id>`，带角色。它和用户走同一套判定，是"系统主体"之外第三种有身份的调用者。0208 留的扩展点由它填上。

### 3.3 本地快路径：bundle v2

只增：旧 SDK 忽略不认识的字段；旧 authz 没有 `contract` 字段时，新 SDK 按 v1 退化（§3.10）。

```json
{
  "contract": "authz/2.0",
  "revision": "18234",
  "capabilities": { "core": true, "admin_write": true, "sharing": true, "relation_sync": true,
                    "check": true, "graph": false, "list_objects": { "max_results": 1000 },
                    "delegation": true, "agents": false, "impersonation": false,
                    "access_review": true, "explain_paths": true, "conditions": false },
  "roles": { "dev_sales_rep": ["erp.sales.view", "erp.sales.cancel", "erp.sales.pricing.read"] },
  "grants": {
    "dev_sales_rep": { "levels": { "erp.sales.view": "subtree", "erp.sales.cancel": "own" } },
    "dev_east_mgr":  { "levels": { "erp.sales.view": "subtree" }, "values": { "org": ["/1/3/", "/1/7/"] } },
    "dev_wh_south":  { "values": { "warehouse": ["7"] }, "until": 1760000000 },
    "superuser":     { "default_level": "all", "values": { "warehouse": ["*"], "legal_entity": ["*"] } }
  },
  "profiles": {
    "agent_sales_ro": { "keys": ["erp.sales.view", "crm.opportunity.view"], "max_level": "subtree",
                        "relations": ["viewer"], "fields": [] }
  },
  "delegations": [
    { "id": "dg_91", "mode": "on_behalf", "from": "u_A", "to": "u_B", "keys": ["infra.workflow.task.act"],
      "from_ts": 1759276800, "until": 1759881600 }
  ],
  "stale_since": { "u_123": 1759400000 },
  "revoked_grants": { "dg_77": 1759401000 },
  "catalog_digest": "sha256:…"
}
```

- 表达力：功能键；档位按键求值，多个角色取最高档；维度取值按键求值、取并集（上一份 §4.5）；`org` 维的取值就是自定义部门子树。
- 字段键本身也是键（`type: field`，§3.9），所以 `roles` 已经覆盖了，不另设结构。
- 委托分两种。`act_as`（agent、扮演）时，token 里的 `ceil` 指向 `profiles`。`on_behalf`（代办）时，B 用自己的 token，SDK 发现 `delegations` 里有 `to == B` 并且覆盖本次键的条目，就把 A 的主体集合并进 B 的。
- `until` 在 SDK 本地按当前时间判定，到期不需要事件（R7）。
- 体积随角色数、profile 数、**活跃**委托数增长，不随人数和记录数增长。共享元组**不进 bundle**，走 changefeed（§3.5）。

### 3.4 Check / BatchCheck

两层，各答各的：

| | 谁答 | 输入 | 能答什么 | 用在哪 |
|---|---|---|---|---|
| **资源级** `POST /{d}/{n}/_authz/check` | 属主组件（SDK 自动挂，`Authenticated`，用调用者 token） | `[{key, type, id}]`，≤ 500 条（同 D8） | 完整决策：规则 + 共享 + 派生 + 委托 + 天花板；`{visible, allowed, reason}` | 跨组件父记录（附件、待办详情）、BFF、前端批量按钮状态 |
| **provider 级** `Check` / `BatchCheck` | authz 成员（系统协议，经 `AUTHZ_URL`） | 主体（claims）+ `[{type, id, relation}]` + `consistency` | 只答"关系是否成立"（含 provider 能做的派生） | 投影水位不够时回落；graph 类型的单条判定 |

资源级的回答遵守 R62：`visible:false` 不区分"不存在"和"看不见"。

一个组件内部判一条记录不需要网络：先加载行，再 `a.Can(key, row)` 本地求值（§4.1）。

### 3.5 列表过滤（核心）

问题：列表的可见性一部分来自规则（行属性，在组件的表里），一部分来自共享和关系（在 authz）。SQL 要在组件自己的库里一次完成，并且分页正确（0205 排除"取回后再过滤"，理由就是分页会错）。

| | (a) ListObjects 取 id 集 | (b) 本地投影 | (c) 混合 |
|---|---|---|---|
| 做法 | 每次列表请求先问 provider "P 以 viewer 关系能看哪些 order"，再 `OR id = ANY(@ids)` | authz 把**直接元组**经 changefeed 下发；SDK 在组件 schema 维护 `besdk_authz_acl`；SQL 里写 `OR EXISTS (SELECT 1 FROM besdk_authz_acl …)`，主体集合在查询时从 token 和 bundle 现算 | 默认 (b)；只有声明了 `derivation: graph` 的类型、并且 provider 有 `graph` 能力时，才额外加 (a)，有上限 |
| 延迟 | 每个列表 +1 次网络往返，再加 provider 计算。OpenFGA 的 ListObjects 是它最贵的 API，默认最多 1000 条、有超时 | 读路径 0 次网络。一次半连接，走索引 `(rtype, rid)`、`(rtype, subject)` | 同 (b)；graph 类型同 (a) |
| 一致性 | provider 一侧强一致 | 最终一致：轮询间隔 ≤ 5 秒，有 NATS poke 时约 100 毫秒；用 zookie 可以补成"读到自己写的" | 同 (b) + 回落 |
| 大集合 | 用户在大团队里时 id 集可达数万：参数膨胀、游标分页要拿全集 | 不受影响：集合在库里 | graph 类型受上限约束，超限答 `RESOURCE_EXHAUSTED`，组件提供更窄的视图 |
| authz 宕机 | 列表要么失败（fail-closed），要么丢掉共享部分 | 投影停在最后一刻，照常工作（fail-static，同 0202） | 同 (b)；graph 部分降级并在响应头标出 |
| principle 1 / 外壳 | 单跑也行，但每个请求都依赖 authz 可达 | 单跑只需要 `AUTHZ_URL`（本来就要拉 bundle），不新增依赖边；外壳里每个成员一张投影表（在自己的 schema 里），拆开后行为相同 | 同 (b) |
| 0202 | 违反（每请求问 authz） | 成立（同属"本地决策点"，数据从轮询换成拉取变更） | 只在声明过的 graph 类型上破例 |
| 存储 | 无 | 只有本组件的类型和它声明继承的外部类型的直接元组；ERP 的共享是稀疏的 | 同 (b) |
| 和 Salesforce 的区别 | — | Salesforce 物化的是**派生**访问（角色层级、组嵌套），组织架构一变就要重算几小时（0205 引用的反例）。本设计**只物化直接元组**，主体一侧（角色、部门祖先、委托人）在查询时展开，换部门只是换一次 token，投影一行都不动 | — |

**推荐 (c)，默认 (b)**。今天的 13 个组件和已登记的规划组件，只用一跳就能满足：共享、团队成员、项目成员、待办处理人。多跳（组套组、文件夹树、项目套项目）是 openfga 成员存在的理由，契约留了位置，但现在不建。

**投影表**（SDK 平台迁移，与 `data-layer.md:352` 的 `besdk_migrations_<schema>` 同一机制，组件不写 DDL）：

```sql
CREATE TABLE IF NOT EXISTS besdk_authz_acl (
    rtype      TEXT        NOT NULL,          -- erp.sales.order
    rid        TEXT        NOT NULL,          -- 行的 id（文本化）
    relation   TEXT        NOT NULL,          -- viewer / editor / member …
    subject    TEXT        NOT NULL,          -- user:u_1 | role:r | dept:/1/12/ | dept_tree:/1/
    expires_at TIMESTAMPTZ,
    revision   BIGINT      NOT NULL,
    PRIMARY KEY (rtype, rid, relation, subject)
);
CREATE INDEX IF NOT EXISTS besdk_authz_acl_subject ON besdk_authz_acl (rtype, subject, relation);
CREATE TABLE IF NOT EXISTS besdk_authz_cursor (
    scope       TEXT PRIMARY KEY,             -- 本组件订阅的类型集合的摘要
    revision    BIGINT NOT NULL,              -- 已完整应用的水位
    rebuilt_at  TIMESTAMPTZ
);
```

**主体集合**（SDK 纯函数，三门语言同构，由决策向量锁定）：

```
S(P) = { user:<sub> } ∪ { role:<r> | r ∈ roles } ∪ { dept:<dept_path> }
     ∪ { dept_tree:<p> | p 是 dept_path 的祖先或自身 }        -- "/1/12/" → "/1/"、"/1/12/"
     ∪ ⋃ { S(委托人) | on_behalf 委托覆盖本次键 }
没有部门（R60）：两个 dept 项都不出现。数组为空就什么都不命中，值层面 fail-closed 天然成立
```

**规范谓词**：SDK 文档给出，组件 SQL 原样照抄，参数全部来自 `Scope.Params()`。仍是静态参数化 SQL：

```sql
AND (
      ( ( @s_all
          OR o.owner_id  = ANY(@s_owners)                  -- own（本人 + 委托人）
          OR o.dept_path = ANY(@s_dept_exact)              -- dept
          OR o.dept_path LIKE ANY(@s_dept_prefix) )        -- subtree + 自定义部门；SDK 已拼 '…%' 并转义
        -- 有资源维度的组件再 AND：(@s_wh_all OR o.warehouse_id = ANY(@s_wh_ids))
      )
   OR ( @s_acl AND EXISTS (
          SELECT 1 FROM besdk_authz_acl a
          WHERE a.rtype = 'erp.sales.order' AND a.rid = o.id::text
            AND a.relation = ANY(@s_relations)              -- 本次键对应的关系（viewer 或更高）
            AND a.subject  = ANY(@s_subjects)
            AND (a.expires_at IS NULL OR a.expires_at > now())) )
   OR o.id::text = ANY(@s_graph_ids)                        -- 只给 graph 类型；其余恒为空数组
)
```

- 只有资源维度、没有 owner/org 维的组件（inventory、finance）：规则分支就是维度条件本身。
- 查询性能不够时（OR 里有 EXISTS 会挡住 owner / dept 索引），SDK 同时给出 `Scope.Branches()`，组件可以改写成 `UNION ALL` 三支、按同一个游标合并。这是性能选项，不改语义；一致性测试按语义断言。
- **列表视图参数**（sales、opportunity 今天的 `view=mine|dept`）：语义变成"在可见集合内收窄"。新增 `view=shared`（只看 acl 分支）和 `view=visible`（并集）。**省略参数时的含义不改**（0302：已有参数不改含义），新的默认值留到下一个大版本。

**跨组件父子**（附件跟随订单、待办跟随单据）：**按父记录检查一次，从不跨父记录做列表过滤**。附件组件"列出订单 42 的附件"，先调 sales 的 `_authz/check`，通过后再列；"列出我能看的全部附件"不支持（写进 0206 的排除项）。这和 Google Drive"先检查文件夹、再列子项"同构。需要跨父列表的类型，只能声明成 graph 类型，交给 graph provider。

### 3.6 关系元组的写入 API 与事件

元组有两种来源，主责不同：

| | authz 主责的元组 | 组件主责的元组 |
|---|---|---|
| 是什么 | 共享（人工授予）、委托 | 业务关系：商机团队、项目成员、待办处理人对单据的临时 viewer |
| 系统记录在哪 | authz | 业务组件自己的表；authz 里是镜像 |
| 怎么写 | 用户调属主组件的 `_shares`；SDK 先在本地检查共享者有没有资格（§4.1），再同步调 provider `WriteTuples`（幂等键、actor、返回 revision） | 业务事务内 `besdk.SyncRelation(tx, …)` 写 outbox，主题 `infra.authz.relation.sync.v1`；按（类型, id, 关系, 来源）整组替换，version 单调。没有双写问题 |
| authz 怎么校验 | 类型和关系在目录里；主体种类允许；写入方 `be-caller` 等于类型的属主组件 | 来源组件等于目录里登记的属主；version 单调（同 `events-consistency.md` §1.2 的 cursor 语义） |
| 管理员能不能直接改 | 能（撤销共享、访问评审） | 不能，只读（改团队成员要去业务组件） |

authz 发布的事件（outbox，JetStream，只增）：

| 主题 | 内容 | 消费者 |
|---|---|---|
| `infra.authz.tuple.changed.v1` | 元组增删、actor（含 `act` 链）、revision | `infra/audit`（将来）；`infra/notification`（"张三把 SO-1001 共享给了你"，链接带 `rev`） |
| `infra.authz.scope_grant.changed.v1` | 档位、取值变更 | 审计 |
| `infra.authz.delegation.changed.v1` | 委托建立 / 撤销 / 到期 | 审计、notification |
| `infra.authz.role.changed.v1`、`user_role.changed.v1` | 已声明、从没发过（上一份 §3.3a），补发并带 `actor_sub` | 审计 |
| `infra.authz.changed.v1` | **poke**：只带 revision，core NATS，丢了也无妨 | 各组件 SDK：立刻拉一次 bundle 和 changes |

**投影靠拉取、事件只是 poke**。拉取：`GET {AUTHZ_URL}/authz/v2/changes?types=…&after=<rev>&limit=500` → `{changes, next, watermark}`；`after` 早于保留期时答 `410`，SDK 用 `ReadTuples` 快照重建，再从快照的 revision 接着拉。

选拉取而不是 JetStream 推送，原因有四：

- 与 bundle 轮询同构：同一个地址、同一个 fail-static。
- 有序、无空洞，续拉令牌就是 revision。
- 安装时的回填和日常同步是同一条代码路径。
- OpenFGA 原生有 `ReadChanges`、SpiceDB 有 `Watch`，适配器很薄。

### 3.7 一致性令牌（zookie）

- provider 的 `revision` 是单调 int64，以十进制字符串传输。所有写入都由成员排序：openfga 适配器自己在 PG 里记写入日志，因为所有写入都经过它。
- `WriteTuples` 返回 revision。属主组件的 `_shares` 在返回前**等自己的投影追到这个 revision**（同步拉一次），共享者自己马上就能看到。
- 别人的后续请求可以带 `X-Authz-Revision: N`（来源：通知链接、前端从写响应里拿到的值）。SDK 的处理：
  - 投影水位 ≥ N：直接查。
  - 水位 < N：同步拉一次 changes，预算 300 毫秒。
  - 仍然 < N：单条读回落到 provider `Check`（`consistency.at_least = N`），列表加响应头 `X-Authz-Consistency: stale`，前端提示"共享刚刚生效，稍后刷新"。
- bundle 也带 revision。管理员授角色以后，响应里返回的 revision 供前端判断"后端是否已经生效"，解决上一份 §3.2 表里"按钮比后端早 15 秒"的问题。
- 水位推进规则：changes 响应带 `watermark`（provider 当前的头）。没有本组件类型的变更时，水位也推进到头，所以"N 是别的类型的写入"不会让 SDK 白等。

### 3.8 Explain

| 层 | 端点 | 谁能调 | 答什么 |
|---|---|---|---|
| 资源级 | `GET /{d}/{n}/_authz/explain?key=&type=&id=` | 本人（只答"我这一侧"的事实）；持 `infra.authz.audit` 的人（完整） | `{decision, reasons:[{kind: role_key\|level\|dimension\|share\|relation\|delegation\|ceiling\|field\|capability, source, detail}], missing:[…]}`。例：缺键 `erp.sales.confirm`（授予它的角色有 X、Y，你都没有）；档位 own，而这张单的负责人不是你；仓库 7 不在你的取值 [3,5] 里；agent 天花板不含此键 |
| provider 级 | `POST /authz/v2/explain`；`GET /api/admin/users/{sub}/access` | 系统；管理员 | 键、档位、取值、委托各来自哪个角色或授予；`explain_paths` 能力下还有关系路径（OpenFGA Expand） |

**R62 约束**：本人调 explain 问一条看不见的记录时，只答"不存在或你无权访问"，再加上本人一侧的事实（档位、维度、缺的键），不透露这条记录的属性。

### 3.9 Admin

经网关的 REST，前端管理页只按这一份契约生成客户端，不认成员：

- 角色：`/api/admin/roles…`（已有）；`PUT /roles/{code}/keys/{key}` `{level}`；`POST|DELETE /roles/{code}/values/{dim}/{value}`；单人用专属角色 `u:<sub>`（已有机制）。
- 字段键：就是 `type: field` 的权限键，进 `registry/permissions.tsv`，管理页按类型分组显示。
- profile（代理人天花板）：`/api/admin/profiles…`；键上标了 `delegable: false` 的（`infra.authz.admin`、`erp.finance.close`、`*.share`）不能放进 profile，authz 拒绝。
- 委托：`/api/me/delegations`（本人发起代办）；`/api/admin/delegations`（管理员查看、撤销）。
- 共享：`/api/me/shares?direction=by_me|with_me`（"共享给我的"跨组件汇总）；`/api/admin/shares?subject=&type=&id=`（评审、撤销）。
- 访问评审：`GET /api/admin/keys/{key}/holders`；`GET /api/admin/access-review?type=&id=`（"谁能看到这张单"）。做法是 authz 向属主组件要规则条件（部门前缀、owner），再按人展开。能力名 `access_review`。
- 本人：`GET /api/me/access`（§6.2 的形状）。
- 系统角色保护、最后一个管理员保护、`superuser` 自动补键：上一份 §3.3。

### 3.10 版本与能力协商

- 契约包 `infra.authz.v2`：proto + OpenAPI + 事件，放在**族契约仓库** `brickKit/contract-infra-authz`（理由见 §5.1）。bundle 的 `contract: "authz/2.<minor>"`，minor 只增。
- **core 能力每个成员必须实现**：claims、键、档位、维度取值、字段键、stale、revision、目录同步、`/api/me/access`、基础 explain、限时授予。
- **可选能力缺失时的明确降级**：

| 缺的能力 | SDK | 前端 | 组装期 |
|---|---|---|---|
| `admin_write` | — | 管理页只读，横幅提示"当前权限实现为静态配置" | — |
| `sharing` | 投影为空；`_shares` 答 `501 {"error":"capability_unavailable","capability":"sharing"}`；`@s_acl=false` | 隐藏共享入口和"共享给我的" | 组件 `requires_capabilities: [sharing]` 时 be-ops 报错 |
| `relation_sync` | `SyncRelation` 照写 outbox；没人消费，事件留在流里，换成员后可以重放 | — | 同上 |
| `check` | 水位不够时，单条读答"不可见 + stale"，不回落 | 提示稍后 | — |
| `graph` | graph 类型的 `@s_graph_ids` 为空，响应头标 `X-Authz-Degraded: graph` | 提示 | 声明 graph 类型的组件要求它 |
| `delegation` / `agents` / `impersonation` | 对应 token（带 `ceil` / `dg`）一律 401 `unsupported_delegation`；`on_behalf` 不展开 | 隐藏入口 | `agents` 还要求 iam 有 `token_exchange` |
| `access_review` / `explain_paths` | — | 隐藏 | — |

- **旧 bundle（v1，没有 `contract` 字段）**：档位按 `subtree`（保持今天的行为），取值为空（fail-closed），能力全部按 false。这正是上一份 §4.7 的过渡规则。
- **未知能力名**：SDK 忽略。新增能力 = 契约 minor + SDK minor。

### 3.11 契约草图

```proto
syntax = "proto3";
package infra.authz.v2;

// provider 契约：每个 authz 成员实现。全部是组件间系统协议（0208）。
// 地址一律来自共享变量 AUTHZ_URL，不建依赖边（0209）。
service AuthzProvider {
  rpc ResolveClaims(ResolveClaimsRequest) returns (ResolveClaimsResponse);   // iam 登录 / 刷新时调
  rpc GetBundle(GetBundleRequest) returns (Bundle);                          // 同 GET /authz/v2/bundle
  rpc ReadChanges(ReadChangesRequest) returns (ReadChangesResponse);         // capability: sharing
  rpc ReadTuples(ReadTuplesRequest) returns (ReadTuplesResponse);            // 快照重建
  rpc WriteTuples(WriteTuplesRequest) returns (WriteTuplesResponse);         // 共享 / 撤销
  rpc Check(CheckRequest) returns (CheckResponse);                           // capability: check
  rpc BatchCheck(BatchCheckRequest) returns (BatchCheckResponse);            // ≤ 500
  rpc ListObjects(ListObjectsRequest) returns (ListObjectsResponse);         // capability: graph
  rpc Explain(ExplainRequest) returns (ExplainResponse);
  rpc CreateDelegation(CreateDelegationRequest) returns (Delegation);        // iam token exchange 调
  rpc RevokeDelegation(RevokeDelegationRequest) returns (Delegation);
}

message Principal {                 // 由调用方 SDK 从已验签的 claims 构造
  string sub = 1; repeated string roles = 2; string dept_path = 3; string tenant_id = 4;
  Actor act = 5; repeated string ceil = 6; string dg = 7;
}
message Actor { string sub = 1; string kind = 2; Actor act = 3; }
message ObjectRef { string type = 1; string id = 2; }
message Tuple {
  ObjectRef object = 1; string relation = 2; string subject = 3;   // user:… | role:… | dept:… | dept_tree:…
  int64 expires_at = 4;                                             // 0 = 不过期
}
message Consistency { string at_least = 1; }                        // revision；空 = 尽快

message ResolveClaimsRequest  { string sub = 1; }
message ResolveClaimsResponse { repeated string roles = 1; string dept_path = 2; string org_id = 3 [deprecated = true];
                                string tenant_id = 4; }
message ReadChangesRequest  { repeated string types = 1; string after = 2; int32 limit = 3; }
message ReadChangesResponse { repeated Change changes = 1; string next = 2; string watermark = 3; }
message Change { string revision = 1; string op = 2; Tuple tuple = 3; }      // op: upsert | delete
message ReadTuplesRequest  { string type = 1; string cursor = 2; int32 limit = 3; }
message ReadTuplesResponse { repeated Tuple tuples = 1; string cursor = 2; string revision = 3; }
message WriteTuplesRequest {
  repeated Tuple writes = 1; repeated Tuple deletes = 2;
  string idempotency_key = 3; Actor actor = 4; string source = 5;       // source = 属主组件 ID
}
message WriteTuplesResponse { string revision = 1; }
message CheckItem { ObjectRef object = 1; string relation = 2; repeated Tuple contextual = 3; }
message CheckRequest  { Principal principal = 1; CheckItem item = 2; Consistency consistency = 3; }
message CheckResponse { bool allowed = 1; repeated Reason via = 2; string revision = 3; }
message BatchCheckRequest  { Principal principal = 1; repeated CheckItem items = 2; Consistency consistency = 3; }
message BatchCheckResponse { repeated CheckResponse results = 1; }
message ListObjectsRequest  { Principal principal = 1; string type = 2; string relation = 3; int32 max = 4;
                              Consistency consistency = 5; }
message ListObjectsResponse { repeated string ids = 1; bool truncated = 2; string revision = 3; }
message Reason { string kind = 1; string source = 2; string detail = 3; }
message ExplainRequest  { Principal principal = 1; string key = 2; ObjectRef object = 3; }
message ExplainResponse { bool allowed = 1; repeated Reason reasons = 2; repeated Reason missing = 3; }
message CreateDelegationRequest {
  string from_sub = 1; Actor to = 2; string mode = 3;                   // act_as | on_behalf
  repeated string profiles = 4; repeated string keys = 5; repeated ObjectRef objects = 6;
  int64 valid_from = 7; int64 valid_until = 8; Actor created_by = 9;
}
message Delegation { string id = 1; CreateDelegationRequest spec = 2; int64 revoked_at = 3; }
message RevokeDelegationRequest { string id = 1; Actor actor = 2; }
message GetBundleRequest {}
message Bundle { bytes json = 1; string etag = 2; }   // 线上格式以 JSON 为准（§3.3），gRPC 只做承载
```

```yaml
# 资源契约：SDK 自动挂载的 REST 片段（besdk-authz.openapi.yaml，由 be-ops 并进每个组件的 openapi）
paths:
  /{prefix}/_authz/check:
    post:
      security: [bearer: []]
      requestBody: { checks: [{ key: string, type: string, id: string }] }       # ≤ 500
      responses: { "200": { results: [{ visible: bool, allowed: bool, reason: string }] } }
  /{prefix}/_authz/explain:
    get: { parameters: [key, type, id], responses: { "200": Explain } }
  /{prefix}/_shares/{type}/{id}:
    get:    { responses: { "200": { shares: [Share] }, "404": NotVisible } }
    post:   { requestBody: { subject: string, relation: string, expires_at: string?, idempotency_key: string },
              responses: { "200": { share: Share, revision: string }, "403": { reason: share_not_allowed },
                           "501": { error: capability_unavailable, capability: sharing } } }
  /{prefix}/_shares/{type}/{id}/{share_id}:
    delete: { responses: { "200": { revision: string } } }
```

---

## 4. SDK 侧

### 4.1 组件唯一使用的 API

本节是 `sdk-redesign.md` 的输入。Go 写法如下，Python、TS 同形，命名按各语言惯例。

```go
// 路由守卫：PermKey 仍然能直接用（今天的写法照样编译）；Guard 加资源语义。
// authzgen 由 be-ops 从 assembly.yaml 生成（§4.2），键和类型都是常量，拼错会编译不过。
besdk.GET(r, "/orders",            authzgen.SalesView.List(authzgen.SalesOrder), h)      // 没有角色键、有共享时：档位 none，只剩 acl 分支
besdk.GET(r, "/orders/:id",        authzgen.SalesView.On(authzgen.SalesOrder, "id"), h)
besdk.POST(r, "/orders/:id/confirm", authzgen.SalesConfirm.On(authzgen.SalesOrder, "id"), h)

// 每个请求一份，替代 ScopeOf / ScopeFrom
a, err := besdk.AccessFrom(ctx)               // 没有用户：ErrUnauthenticated（REST 401 / gRPC Unauthenticated）
u := a.User()                                 // 身份：建单快照的部门从这里取，不从范围取（上一份 §4.2 第 2 条）
a.Has(authzgen.SalesPricingRead) bool         // 功能键，已经计入天花板

// 列表
sc := a.Scope(authzgen.SalesOrder)            // 按本路由的键求值：档位、取值、主体集合、关系、acl 开关、graph ids
repo.ListOrders(ctx, sc.Params(), filters)    // Params 结构体字段与规范谓词的 @s_* 一一对应

// 单条：行实现 besdk.Resource
type Resource interface { AuthzRef() besdk.Ref; AuthzAttrs() besdk.Attrs }
type Attrs struct { Owner, DeptPath string; Values map[string]string }   // values: warehouse → "7"
d := a.Can(authzgen.SalesConfirm, order)      // 本地求值：规则 + 投影 + 委托 + 天花板
if !d.Visible { return repo.ErrNotFound }     // R62 细化（Q3）：看不见一律 404
if !d.Allowed { return d.Err() }              // 403，带 reason

// 行按钮：列表响应里每行带 _access，前端不猜
acts := a.RowActions(authzgen.SalesOrder, orders, authzgen.SalesConfirm, authzgen.SalesCancel)

// 字段
a.Mask(&dto)                                  // 按 struct tag `be:"field=erp.sales.pricing"` 置 null，写 _masked:["unit_price"]
if err := a.CheckWritable(authzgen.SalesOrder, changed); err != nil { … }   // 改了掩码字段：403 field_forbidden
a.CheckSortable(sortField)                    // 按掩码字段排序 / 过滤 / 聚合：拒绝（否则按顺序就能推出值）

// 共享：声明了 share 的类型，SDK 自动挂 _shares，组件只给一个加载器
besdk.MountSharing(r, rt, authzgen.SalesOrder, func(ctx context.Context, id string) (besdk.Resource, error) { … })
// 组件主责的关系：在业务事务里调，走 outbox
besdk.SyncRelation(tx, authzgen.OpportunityTeam, oppID, subjects, version)
// 能力
besdk.Capabilities(ctx).Has("sharing")
```

**共享资格**（`_shares` POST 里 SDK 本地判，判过才调 `WriteTuples`）：

- 共享者持有该类型的 share 键（`erp.sales.share`）。
- 共享者对这条记录当前至少持有要授出的那个关系所含的全部键。这是 Dynamics 的"只能共享自己有的权限"。
- 关系 ∈ 类型声明里允许共享的关系；主体种类 ∈ 允许的主体种类。
- 当前主体是 agent 时，profile 必须允许共享。默认 share 键 `delegable: false`。

### 4.2 在 `assembly.yaml` 里声明（与 `data_scopes` 并列）

```yaml
data_scopes:                                          # 不变：规则跟版本（0205）
  - { dimension: org,   column: dept_path, mode: prefix, tables: [sales_orders] }
  - { dimension: owner, column: owner_id,  mode: equals, tables: [sales_orders] }

permissions:
  - { key: erp.sales.view,          title: 查看销售订单, type: page }
  - { key: erp.sales.confirm,       title: 确认订单,     type: action }
  - { key: erp.sales.share,         title: 共享订单,     type: action, delegable: false }
  - { key: erp.sales.pricing.read,  title: 查看订单价格, type: field }
  - { key: erp.sales.pricing.edit,  title: 修改订单价格, type: field }

resources:                                            # 新段；data_scopes: none 的组件可以省略
  - type: erp.sales.order                             # <domain>.<name>.<aggregate>，全局唯一归属（I8 推广）
    table: sales_orders
    keys: [erp.sales.view, erp.sales.confirm, erp.sales.cancel, erp.sales.ship]
    relations:
      viewer: { grants: [erp.sales.view] }            # 共享 viewer = 对这一条有 view
      editor: { includes: [viewer], grants: [erp.sales.ship] }
    share:
      key: erp.sales.share
      relations: [viewer, editor]
      subjects: [user, role, dept, dept_tree]
    fields:
      - { set: erp.sales.pricing, columns: [unit_price, discount, total_amount],
          read: erp.sales.pricing.read, edit: erp.sales.pricing.edit }
    inherits: []                                      # 一跳派生：例如 prj/timesheet 的 { from: prj.project.project, via: project_id, relation: member → viewer }
    derivation: direct                                # direct（默认）| graph（要求 provider 的 graph 能力）

requires_capabilities: []                             # 例：协作类组件写 [sharing]
```

- 每条关系的 `grants` 是否要包含功能键，由组件作者声明（Q1 定默认）。动作键（confirm、cancel、close）是否允许经共享获得，也在这里显式写出。
- 组件主责的关系写成 `relations: { member: { owned_by: component, grants: […] } }`，authz 据此拒绝管理员直接改这条关系。
- **be-ops** 的工作：
  - 校验：类型唯一归属；`keys` 都是本组件的键；`inherits.from` 必须是已登记的类型；`field` 类型的键只能出现在 `fields`。
  - 派生登记表 `registry/resource-types.tsv`（只增），作为 authz 的 `RESOURCE_CATALOG`。做法同 `PERMISSION_CATALOG`，也就是 `config/infra-authz.yaml:9` 那一行。
  - 生成 `authzgen`：Go `backend/internal/authzgen/authzgen.go`、Python `backend/app/authzgen.py`、TS `src/authzgen.ts`。
  - gate `authzgen-fresh` 检查生成物和 `assembly.yaml` 是否一致。
- 为什么用生成代码，而不是让 SDK 运行时读 `assembly.yaml`：外壳镜像里的成员是编译进去的；运行时读文件，要么得在镜像里多带一份清单，要么有路径问题。生成的常量编译期就到位，还能顺手消灭拼错的键（今天 `PermKey` 是裸字符串）。

### 4.3 缓存与失效

| 数据 | 存在哪 | 怎么失效 | 最长时延 |
|---|---|---|---|
| bundle | 进程内存（外壳里整个进程一份，`shell.go:72` 已经是这样） | ETag 条件轮询 15 秒 + `infra.authz.changed.v1` poke 触发立刻拉 | poke 正常时约 1 秒，丢了 15 秒 |
| 投影 | 组件 schema 的 `besdk_authz_acl` | changes 拉取 5 秒 + poke；`410` 时重建 | 约 0.1–5 秒；zookie 可以补成读到自己写的 |
| 到期 | 不缓存，读时比 `now()` | 不需要事件；清扫任务只做清理 | 0 |
| 身份 / 角色 / 部门 / 委托撤销 | token + `stale_since` / `revoked_grants` | 401 token_stale 后静默刷新（改部门也写 stale，上一份 §3.3d） | 约 15 秒 + 一次刷新 |
| 远程 Check 结果 | **只在本请求内**备忘 | — | — |
| 资源级 `_authz/check` 的结果 | 调用方不缓存 | — | — |

0201 不变：没有 Redis，也没有跨请求的决策缓存。决策缓存是最容易做错的东西（撤销以后还在放行），收益只有省掉一次内存查找。

### 4.4 一致性令牌在 SDK 里

- 入站：中间件读 `X-Authz-Revision`，放进 `Access`；`Scope()` / `Can()` 需要投影时检查水位，按 §3.7 处理。
- 出站：`_shares` 写入、管理 API 的写入响应都带 `revision`。前端把最近一次见到的 revision 放进后续请求的头里（只给同一组件的请求；跨组件的场景用通知链接里的 `rev`）。
- BFF 原样透传这个头（`UserHTTP` 助手自动带上）。

### 4.5 外壳里的行为

- bundle、验签器整个进程一份（已有）。能力只有一份。所有成员的 SDK 版本是同一个（MVS），不会出现"成员 A 认 v2.1、成员 B 认 v2.0"。
- 投影：每个成员在**自己的 schema** 里一张表、一个拉取协程，只拉自己声明的类型（含 `inherits` 的外部类型）。可以合并成进程级一个拉取器再分发，但不合并：拆开以后行为必须一模一样（0108"外壳只是把 N 个进程变成一个"）。
- 资源级 `_authz/check`：外壳里也打成员自己的 HTTP 端口（`ShellModuleConfig.HTTPPort`），不走进程内调用（0101）。
- poke：每个成员各订阅一次 core NATS。消息很小，重复无妨。
- authz 自己也在 go-infra 外壳里时：组件经 `AUTHZ_URL` 打 authz 成员自己的服务名（0107 已有规则），不打外壳的服务名。

### 4.6 测试辅助（`besdktest`）

- `WithUser(ctx, u, WithLevel(key, "own"), WithValues("warehouse", "7"), WithCeil(profile), WithDelegation(…), WithCapabilities(…))`。
- `InsertACL(t, db, schema, tuple…)`：直接往投影表写元组，组件的 L2 测试不需要真的 authz。
- `FakeProvider`：进程内的 provider 契约实现，供 SDK 自测和组件 L3 测试用；它本身也要跑一致性测试 core（§5.4），否则夹具会和真实现漂移。

### 4.7 新易错点（落地时写进根 `AGENTS.md` 的 Pitfalls 表）

| 绝不 | 症状 | 原因 |
|---|---|---|
| 列表 SQL 漏了 acl 分支，而 `Can` 有 | 共享给我的单点链接能打开，列表里却没有；反过来漏在 `Can` 里，就是列表能看、点开 404 | List/Can 一致性；一致性测试会抓到 |
| 按掩码字段排序、过滤、聚合 | 按成本排序就能推出成本区间；汇总金额泄露单价 | `CheckSortable`；汇总值跟随字段键 |
| agent 或代办路径用系统身份取数 | agent 看到用户看不到的行，天花板被绕过 | agent 只能拿 act-as token 走 REST；系统身份只用于系统协议（0208） |
| 绕过属主组件直接调 `WriteTuples` 做共享 | 没人检查"共享者自己有没有这个权限"，权限借共享放大 | 共享只经 `_shares`；provider 校验 `be-caller` 等于属主 |
| 跨请求缓存 `Can` 的结果 | 撤销共享后照样放行 | §4.3 |
| 事件 payload 原样展示给用户 | 通知正文带出价格 | 事件是系统面，展示给人之前要按接收者掩码，或者只放链接 |
| 改列表 `view` 参数在省略时的含义 | 旧前端、BFF 静默看到不同的集合 | 0302 |

---

## 5. 槽位族

### 5.1 为什么 authz 能成为槽位族，以及先要做什么

- **0104 (a) 成立**：成熟系统确实用三种不同方式实现授权，各自适合不同客户。一是 RBAC + 范围（若依、Dynamics、ERPNext），二是 ReBAC（Zanzibar 系），三是策略语言（Cedar、OPA）。还有第四类客户只要一份静态文件（小型部署、边缘、演示）。
- **0104 (b) 今天不成立**：`infra/iam-casdoor` 声明了 `dependencies.components: [infra/authz@2.0.1]`（`component.yaml:26`），为的是调 `ResolveClaims`。按 brickKit 规则（`docs/en/09-patterns/01-component-design.md:116-123`），一旦有人依赖了一个成员，它就不可替换。
  - **解法**：iam 改读共享变量 `AUTHZ_URL`（`config/vars.yaml` 一行，同 `AUTHZ_BUNDLE_URL` 的做法，`config/vars.yaml:22`）。0107 的 rules-out 里"不声明依赖就调 authz 的 gRPC"一条要改写成"authz 族的全部契约只经 `AUTHZ_URL` 访问，任何组件都不得依赖 authz 族的成员"。
  - `AUTHZ_BUNDLE_URL` 保留一版，由 `AUTHZ_URL` 派生，然后标弃用。
- **族契约放哪**：0101 只允许 `be-sdk-*` 和"某个组件自己的 gen 包"跨边界。族契约不属于任何一个成员（iam 族今天的 `contracts/infra/iam/v1` 放在 casdoor 成员仓库里，加了 keycloak 就会尴尬）。推荐新建 `brickKit/contract-infra-authz`（proto、OpenAPI、事件、能力枚举、决策向量），成员、SDK、前端生成器都从这里取。0101 的 revisit 条件（无业务逻辑、无组件语义、每个进程只能有一份）它都满足，0101 增补"族契约包"作为第三类。iam 族顺手照做（`contract-infra-iam`），不在本文范围内。
- **前端管理页按族契约生成**，按能力降级。0104 已列的 `slot:frontend` 不受影响。

### 5.2 成员

| 成员 | 存储 | 能力 | 适合谁 | 它证明什么 |
|---|---|---|---|---|
| **`infra/authz`**（原生，默认；ID 不改） | PG：现有表 + `role_key_levels`、`role_scope_values`、`resource_types`、`tuples`、`tuple_log`（BIGSERIAL = revision，按保留期截断）、`profiles`、`delegations` | core + `admin_write` `sharing` `relation_sync` `check` `delegation` `agents` `impersonation` `access_review` `explain_paths`；`graph=false`；`list_objects` 只到一跳 | 绝大多数 ERP / CRM 客户 | 完整契约可以在单机 PG 上实现，没有新增基础服务（0201） |
| **`infra/authz-static`** | 无库；`AUTHZ_POLICY_FILE: file://config/authz-policy.yaml`（角色、键、档位、取值、用户→角色、部门） | 只有 core；`admin_write=false`、`sharing=false`；改文件后重载，全员 stale | 十人以下、演示、边缘、离线，也是测试夹具 | **可替换**：前端和 SDK 不改一行就能换上；**明确降级**：每一个缺失的能力都有可见、可测的行为 |
| **`infra/authz-openfga`** | OpenFGA 服务（按 0106 是基础设施，`make up` 的一个可选 profile）+ 适配器自己的 PG（键、档位、取值、写入日志、委托） | core + `sharing` `relation_sync` `check` **`graph`** `list_objects` `explain_paths`（Expand）+ 访问评审（ListUsers） | 协作重的客户：项目、文件夹、嵌套团队、跨组织共享 | ReBAC 可以放在同一份契约后面；graph 类型、zookie 与 provider 的一致性参数对得上 |
| `infra/authz-cedar`（或 OPA） | 策略文件 / Verified Permissions 风格 | core + 共享（用 Cedar 的 policy template link 表示）+ `conditions`（**只用于动作判定**） | 有真实 ABAC 规则的客户（金额阈值、时间窗、IP） | 策略语言可以放在后面。**限制**：条件不能参与可见性，否则 List/Can 一致性需要部分求值翻成 SQL（OPA compile、Cedar partial evaluation 目前都不成熟），这一条写进 0209 的 Revisit |

openfga 适配器的映射（说明契约可以实现，不是现在要做）：

- 资源目录生成 OpenFGA 模型：`type erp.sales.order`、`define viewer: [user, role#member, dept#member, dept_tree#member] or editor`。
- 主体展开（我的角色、部门祖先）作为 **contextual tuples** 随请求发送，不把用户角色同步进 OpenFGA。
- changefeed 用适配器自己的写入日志；也可以用 OpenFGA `ReadChanges`，但它的令牌是不透明的，拿来做 revision 比较不方便。
- 选 OpenFGA 而不是 SpiceDB，理由有三：PG datastore 与本栈一致；`ListObjects`、`ListUsers`、`ReadChanges` 都现成；CNCF 项目。SpiceDB 同样能过这套一致性测试，作为备选成员登记。

### 5.3 顺序与理由

1. **原生 `infra/authz` 升级到 v2**（P0 core，P1 共享）：所有组件依赖它的行为。
2. **`infra/authz-static`**（P1，随 06c）：大约一周的工作量。没有它，"可替换"只是纸面。06c 的前端降级要用它真机验证一次。
3. **`infra/authz-openfga`**（P3）：触发条件是 `prj/project` 进入开发，或者用户决定在阶段 07 单独做一次"替换演示"（Q6）。
4. **cedar / OPA**：不排期，有真实需求才建。

### 5.4 一致性测试套件

**位置**：`tools/be-acceptance/authzconf/`。被测的成员仓库在 `Makefile` 里写 `make conformance`，用钉死版本的 be-acceptance 作为 Go module 运行；父仓库 `make conformance-authz MEMBER=<id>` 用 `brickkit up --focus <id>` 起被测成员，再跑套件，结果写进测试记录。

**三层**：

| 层 | 内容 | 怎么跑 | 断言什么 |
|---|---|---|---|
| ① 决策向量 `authzconf/vectors/*.json` | `{bundle, claims, route_key, resource_attrs, acl_rows, now, revision}` → `{decision, scope_params, subjects, field_mask, reasons}`，几百条 | 三门 SDK 各有一个测试读同一组向量。Python、TS 用 `make sync-vectors` 从 be-acceptance 的 tag 拷过去（拷的是测试数据，不是代码） | 三门 SDK 的档位取最高、按键求值、主体展开、R60（没有部门时数组为空）、委托合并、天花板交集、到期、v1 bundle 退化，结果逐字相同 |
| ② provider 黑盒 `authzconf/provider` | 套件自带一个测试 JWKS 签发器，被测成员的 `IAM_JWKS_URL` 指向它；用夹具目录（`conformance.widget.item` 类型、键、维度）初始化 | `go test ./authzconf/provider -args -authz-url=… -admin-sub=…` | 按 `capabilities` 分组：**core** 必过；声明了的可选能力必过；**没声明的**，断言对应端点答 `501 capability_unavailable` 并带能力名，bundle 里对应项为 false |
| ③ 端到端 `authzconf/e2e` | 夹具组件 `be-acceptance/fixtures/widget`（Go，用真 SDK、规范谓词、投影），和被测成员一起起 | 属性测试：随机生成角色、档位、取值、共享、委托、到期，再随机生成行 | **List/Can 一致**；共享以后，带上 revision 立刻可见；撤销以后不可见；到期以后不可见；部门子树共享；天花板外的键答 403；掩码字段为 null 且在 `_masked` 里；按掩码字段排序被拒绝 |

**core 组里的代表用例**（命名沿用中文测试名惯例）：

- `TestConformance_目录同步_新键出现在bundle_退役键不出现`
- `TestConformance_档位_多个角色取最高`、`TestConformance_档位_授了键没写档位按own`
- `TestConformance_取值_星号表示全部且只能显式授予`
- `TestConformance_stale_授撤角色改部门后旧token变stale`
- `TestConformance_限时_过期的角色和取值不再出现`
- `TestConformance_revision_任意写入后单调递增`
- `TestConformance_系统角色不可删_最后一个管理员不可撤`（`admin_write` 组）
- `TestConformance_ResolveClaims_带typ所需字段与tenant_id`

**sharing 组**：

- `TestConformance_WriteTuples_同一幂等键重放返回同一revision`
- `TestConformance_changes_断点续拉无空洞且watermark推进`
- `TestConformance_changes_早于保留期答410且ReadTuples可重建`
- `TestConformance_WriteTuples_非属主来源写入被拒`
- `TestConformance_组件主责关系_旧version被丢弃`

**降级组**（拿 static 跑）：

- `TestConformance_未声明sharing_共享端点答501且带能力名`
- `TestConformance_未声明admin_write_管理写接口答501`

**输出**：一张能力矩阵（成员 × 能力 × 通过 / 降级正确 / 失败），写进 `dev/test-records/` 的测试记录。

**gate**：`make gates` 加 `authz-capability-scan`：各组件的 `requires_capabilities` ⊆ 已装 authz 成员 `assembly.yaml` 里声明的 `provides_capabilities`。

---

## 6. 对现有 13 个组件与前端的影响

### 6.1 组件

| 组件 | 必须声明 | 必须改 | 阶段 |
|---|---|---|---|
| **infra/authz** | `provides_capabilities`；`RESOURCE_CATALOG`、`DATA_SCOPE_CATALOG` 配置键 | v2 契约全部：档位、取值、字段键、能力端点、ResolveClaims v2、outbox 审计事件、改部门写 stale、superuser 自动补键、系统角色保护（上一份 §3.4）→ P0；元组、changes、WriteTuples、Check、`_shares` 的服务端、`/api/me/shares`、Explain → P1；委托、profile、访问评审 → P2–P3 | P0–P3 |
| **infra/iam-casdoor** | 去掉 `dependencies.components: [infra/authz@2.0.1]`；新增 `AUTHZ_URL` | `typ: access`、`tenant_id`（P0）；token exchange（`act`、`ceil`、`dg`）、扮演、服务账号（P3） | P0 / P3 |
| **erp/inventory** | `resources: [erp.inventory.balance, …]`，`share` 不声明（不可共享） | 删 `warehouse_access` 表和 `/warehouse-access/*` 三个端点（I7）；`a.Scope()` 的 warehouse 取值；`erp.inventory.manage_access` 的含义改成"能列出全部仓库以便分配"（上一份 §4.5）；gRPC 面答 Unauthenticated（上一份 §5.4） | P0 |
| **erp/finance** | 同上（`legal_entity`） | 删 `legal_entity_access`（I7）；信用敞口按法人限定（I9） | P0 |
| **erp/sales** | `resources: erp.sales.order`（可共享，viewer / editor）；字段 `erp.sales.pricing`；键 `erp.sales.share`、`erp.sales.pricing.read/edit` | 规范谓词（P0 就带 acl 分支，投影为空）；`checkOrderInScope` 换成 `a.Can`；`cancel@own` 这类按键档位；快照部门取 `User`；`view=shared|visible`；R62 细化（Q3）；`MountSharing`（P1）；`Mask` 价格（P1）；列表 `_access` 行按钮（P1） | P0 / P1 |
| **crm/opportunity** | `resources: crm.opportunity.opportunity`（可共享）；预留关系 `member: { owned_by: component }`（商机团队，功能本身以后再做） | 同 sales；团队功能上线时 `SyncRelation` | P0 / P1 / 以后 |
| **infra/workflow** | `resources: infra.workflow.task` | `.admin` 退役，换成 `all` 档（旧路由保留，同一实现）；代办：`on_behalf` 委托让 B 看到并处理 A 的待办（P2）；建待办的**业务组件**在同一事务里 `SyncRelation(单据, viewer, 处理人, until=待办关闭)`，处理人在待办打开期间能看单据（P2，这是 R4 的派生例子） | P0 / P2 |
| **infra/notification** | `resources: infra.notification.record` | `.admin` → `all` 档；消费 `infra.authz.tuple.changed.v1` 发"共享给你"的通知，链接带 `rev`（P1） | P0 / P1 |
| **mdm/product** | 字段 `mdm.product.cost`（`standard_cost`）；键 `mdm.product.cost.read/edit`（`type: field`） | `Mask`；gRPC 写面收紧（I5）。迁移给现有所有带 `mdm.product.view` 的角色授 `cost.read`，行为不变；之后由管理员收回 | P0（gRPC）/ P1（字段） |
| **mdm/customer** | 字段 `mdm.customer.credit`（`credit_limit`） | 同上 | 同上 |
| **infra/print** | `data_scopes: none`，不变 | 不做判定：数据由调用方给，**调用方在送去渲染之前已经掩码**（写进 print 的 `BRICKKIT.md` "Before you deploy"） | — |
| **infra/bff-mobile** | — | 只留 `infra.bff-mobile.use`，resolver 用下游的键（I6）；透传 `X-Authz-Revision`；能力取自 `/api/me/access` | P1 |
| **integration/im-dingtalk** | — | 不动 | — |

**R60 哨兵**：规范谓词用数组参数，没有部门时 `@s_dept_exact`、`@s_dept_prefix` 都是空数组，天然什么都不命中，不再依赖哨兵值。`ScopeFilter.Prefix` / `Exact` 的哨兵保留到旧 API 删除（SDK 清理版本），供还没迁移的旧代码用。

**R62 细化（Q3）**："看不见"（规则、共享、派生都不成立）时读和命令一律 404；"看得见但做不了"时 403，带 reason。GitHub 对私有仓库就是这样，任何动作都答 404。今天命令答 403（`erp-sales.md:193`），等于用命令就能探出一条记录是否存在。改了以后 sales、workflow 各有 1–2 条测试要单独提交改名（`TestApprove_范围外仍是403` → `…范围外是404`）。

### 6.2 前端（06c）

- **`/api/me/access` v2** 一次给全：
  ```json
  { "sub": "u_1", "act": null, "dept": { "path": "/1/12/", "has_dept": true },
    "components": ["erp/sales"], "capabilities": { "sharing": true, "admin_write": true, "delegation": true },
    "keys": { "erp.sales.view": { "level": "subtree" }, "erp.sales.cancel": { "level": "own" } },
    "values": { "warehouse": ["3", "5"] }, "fields": ["erp.sales.pricing.read"],
    "ceil": [], "delegations": { "to_me": [{ "from": "u_A", "keys": ["infra.workflow.task.act"], "until": "…" }] },
    "revision": "18234" }
  ```
  它替代 `/api/tenant/features` ∩ `/api/me/permissions` 两次请求（I3）。`stores/access.ts`（`apps/pc/src/stores/access.ts`）改读它。
- **按钮**：`v-be-auth` 仍然判功能键；行级按钮读列表响应的 `_access`（`useRowCan(row, 'confirm')`），不在前端拼规则。
- **字段**：表格列配置按 `fields` 隐藏列；详情页里 `_masked` 中的字段显示"***（无权查看）"，和空值区分开。
- **共享**：ui-kit-pc 新增 `<BeShareDialog :component :type :id>`，AntDV 只出现在 ui-kit 里（0402）。主体选择器要用到用户、角色、部门三个目录接口（iam 用户搜索、authz 角色与部门）。显示条件：`capabilities.sharing` 为真、该类型可共享、持有 share 键。
  列表页模板加"共享给我的"页签（`view=shared`）和"共享"按钮。顶栏新增"共享给我的"汇总页，读 `/api/me/shares`。
- **"为什么"**：404 / 403 页面和列表空态提供"为什么看不到"抽屉，读 `_authz/explain` 和 `/api/me/access`，按 §3.8 的 R62 约束显示。
- **管理页**：
  - 角色 × 键的档位矩阵；维度取值选择器（仓库列表调 inventory `GET /warehouses?all=true`，需要 manage_access 键）。
  - 字段键单独分组。
  - profile、委托（"我的代理人"放在个人设置里）、共享评审、访问评审。
  - `!admin_write` 时只读。
- **一致性**：写共享以后，把响应里的 `revision` 带进同一组件后续请求的 `X-Authz-Revision`；收到 `X-Authz-Consistency: stale` 时轻提示。
- **06c 开工前要冻结的**：`/api/me/access` v2 的形状、`besdk-authz.openapi.yaml` 片段（`_shares`、`_authz/check|explain`）、能力名枚举。后端可以晚于前端实现，前端先对 static 和 fake provider 开发。

### 6.3 决策记录

phase 06 期间写或改的决策原地改写、保留编号（`docs/en/02-decisions/README.md:13`）。0207、0208 只在上一份里起草过、从没发布，编号可以照用。

| 编号 | 动作 | 要点 |
|---|---|---|
| 0101 | 增补 | 第三类可以跨边界的包：**族契约包**（只有 protoc 产物和契约文件，没有逻辑） |
| 0104 | 增补 | 槽位列表加 `slot:authz`；举例说明"把成员的依赖边换成共享变量"是让一个位置满足 (b) 的标准手法 |
| 0107 | 改写 | authz 族的**全部**契约（bundle、changes、check、写、ResolveClaims）只经 `AUTHZ_URL` 访问，任何组件都不得依赖 authz 族的成员；iam→authz 的边删除；IAM 族同理（`IAM_JWKS_URL` 已经是这样） |
| 0202 | 改写 | 本地决策点覆盖键、档位、取值、字段、天花板（bundle）和直接元组（投影，拉取）；"每请求问 authz"只允许两种情况：声明的 graph 类型、一致性回落。rules-out 里"SpiceDB / OpenFGA"改成"作为业务组件的直接依赖或热路径服务"；它们可以作为槽位成员 |
| 0203 | 增补 | 允许的身份 claim：`typ`、`tenant_id`、`act`、`ceil`、`dg`、`azp`；`ceil` 是码不是键 |
| 0204 | 增补 | 纯并集只在一个主体内部；委托链上取交集（天花板），这不是 Deny：没有规则顺序，解释仍然唯一 |
| 0205 | 原地重写 | "数据范围的**规则**随版本"（`data_scopes`、`resources` 必填，规则不可在运行时编辑）；删掉"不许有编辑谁看哪些行的管理界面"和"共享就是改 `owner_id`"两条（已被现状和新需求推翻），指向 0207 |
| 0206 | 原地重写 | "不用 RLS；共享引擎只有一个，在 authz，由 SDK 投影进组件；组件不手写共享表、不复制组织树"；新增排除项"跨父记录的继承可见性做列表过滤（只能按父检查）"；Revisit："一跳加主体展开表达不了，且没有 graph provider" |
| **0207**（新） | 照上一份起草并扩大 | 档位（own / dept / subtree / all）、维度取值（含 `org` 自定义部门）、共享、委托都是 authz 里的运行时**分配**；组件不建授权表、不建分配管理 API、不用权限键扩大范围 |
| **0208**（新） | 照上一份 | gRPC 是组件间系统协议 |
| **0209**（新） | 新 | authz 是一个槽位族，族契约 `infra.authz.v2`、能力协商、一致性测试套件；列表过滤默认走本地投影；List/Can 一致是契约的一部分；ABAC 条件不参与可见性 |
| **0210**（新） | 新 | 委托、扮演、代理人：`act` / `ceil` / `dg`，有效权限 = 用户 ∩ 天花板，**每次请求现算、不快照**；`delegable: false` 的键不能下放；agent 永远不用系统身份取用户数据 |
| **0211**（新） | 新 | 字段级权限是 `type: field` 的键，在源头掩码（属主组件），排序 / 过滤 / 聚合跟随字段键；事件不是展示面 |

### 6.4 I1–I10 重答

| # | 上一份的推荐 | 新要求下 | 变化 |
|---|---|---|---|
| I1 | 分配集中进 authz（0207） | **做，而且是契约 core 的一部分**：每个成员都必须实现档位和取值，否则 static 成员换上来以后 inventory 一行都看不到 | 加强 |
| I2 | 先不要 `dept` | **现在就加**。规范谓词用数组参数，`dept` 只是 `dept_path = ANY(@s_dept_exact)` 一个分支，由 SDK 统一给出，所有组件同时支持；若依、Dynamics 都有这一档，没有它就比若依弱。"自定义部门"也做，作为 `org` 维的取值 | **改判** |
| I3 | `/api/tenant/features` 收窄，并进 `/api/me/access` | 照推荐；`/api/me/access` 再加能力、字段、委托、revision | 不变 |
| I4 | `BOOTSTRAP_ADMIN_SUB` | 照推荐；static 成员的管理员写在策略文件里 | 不变 |
| I5 | mdm 的 gRPC 写面收紧 | 照推荐；agent 时代更要紧，系统面不能被当成用户写入的旁路 | 不变 |
| I6 | 只留 `infra.bff-mobile.use` | **照推荐，理由更强**：天花板、字段掩码、共享都只能由属主组件判；BFF 自己的键会形成第二套判定，并且会和 agent 天花板打架 | 加强 |
| I7 | 2.1.0 直接删 inventory、finance 的授权表 | 照推荐 | 不变 |
| I8 | 资源维度唯一归属 | 照推荐，并推广到**资源类型**（`resource-types.tsv` 的属主列），因为共享写入的来源校验靠它 | 推广 |
| I9 | 信用敞口按法人限定 | 照推荐；额度数值另外声明为字段键 | 加强 |
| I10 | `tenant_id`，`org_id` 弃用 | 照推荐，与 `typ`、`act`、`ceil`、`dg`、`azp` 在同一版 claims 里一起加，iam 只改一次 | 合并 |

---

## 7. 落地顺序

前提：本文先于 `sdk-redesign.md`。§4 是它的输入，SDK 的版本号由它定，这里只写"哪个 SDK 能力"。

### P0：组外壳（T21–T24）之前必须完成

判据：缺了它，以后要么改契约，要么把组件的 SQL 和调用点再改一遍。

1. **决策**：0205、0206 重写；0207–0211 定稿；0101、0104、0107、0202、0203、0204 增补；中英镜像，`make docs-mirror`。
2. **族契约** `contract-infra-authz` v2.0：proto、OpenAPI、事件、能力枚举一次写全，可选部分只写形状。决策向量第一批（core）。
3. **be-ops**：`resources` / `requires_capabilities` / `type: field` / `delegable` 的校验；`registry/resource-types.tsv`；`authzgen` 生成器；gate `authzgen-fresh`。
4. **SDK**（三门，并入 `sdk-redesign`）：`AccessFrom` / `User` / `Has` / `Scope`（数组参数，带 acl 分支和 graph 分支的形状）/ `Can` / `Resource`；能力读取与降级；v1 bundle 退化；平台迁移建 `besdk_authz_acl` / `besdk_authz_cursor`（声明了 `resources` 的组件才建）；changes 拉取器（P0 就带上；`sharing=false` 时不启动）；`X-Authz-Revision` 中间件；`besdktest`；三门都过决策向量。
5. **infra/authz**：§6.1 的 P0 一栏；`provides_capabilities` 先声明 core + `admin_write`。
6. **infra/iam-casdoor**：删依赖边，改 `AUTHZ_URL`；`typ`、`tenant_id`。
7. **组件**：inventory、finance 删本地授权表；sales、opportunity、workflow、notification 用规范谓词与按键档位；`.admin` 退役；R62 细化（如果 Q3 同意）；mdm 收紧 gRPC 写面。
8. **be-acceptance**：一致性测试 ① 向量层、② provider 层 core 组，对原生成员跑通；gate `authz-capability-scan`。
9. 外壳：`go-infra` 的成员列表照常，不受影响（authz、iam 只是新版本）。

### P1：与 06c 同步

- authz：`sharing`、`check`、`explain_paths`、`/api/me/shares`、tuple 事件、poke。
- SDK：`MountSharing`、`Mask` / `CheckWritable` / `CheckSortable`、`RowActions`、`_authz/check|explain`。
- sales、opportunity 开启共享；product、customer、sales 开启字段掩码；notification 发"共享给你"的通知。
- **`infra/authz-static`** + 一致性测试降级组；06c 的前端对 static 真机验证一次降级。
- 一致性测试 ③ 端到端（widget 夹具），对原生和 static 两个成员各跑一次，出能力矩阵。

### P2：06c 之后

- 委托 `on_behalf`（代办）；workflow 建待办时给处理人写派生 viewer；访问评审；`infra/audit` 消费审计事件（如果那时已经有这个组件）。

### P3：按触发条件

- agent 与扮演（`ana/ai` 开发时）：iam token exchange、profile、`revoked_grants`。
- `infra/authz-openfga`：`prj/project` 开发时，或者阶段 07 做替换演示（Q6）。
- cedar / OPA：只在有需求时。

全部只增：P1–P3 不改 P0 定下的契约形状、SQL 形状和 SDK 调用形状，只是打开能力、新增端点。

### 先写的红测试

**P0**：

- SDK（三门同名）：
  - `TestVectors_core全部通过`（今天红：没有档位、取值、主体展开）
  - `TestScope_没有部门时部门数组为空`
  - `TestScope_dept档只命中本部门不含下级`
  - `TestScope_自定义部门取值并入前缀数组`
  - `TestScope_按路由键求值_调整键只授南仓`
  - `TestBundle_v1格式退化为subtree且取值为空且能力全假`
  - `TestCan_与Scope对同一行结论一致`（性质测试）
  - `TestAccessFrom_没有用户答Unauthenticated`
- authz：
  - `TestBundle_v2带档位取值能力与revision`
  - `TestResolveClaims_带tenant_id`
  - `TestAssignUserDepartment_写stale`
  - `TestCatalogSync_资源类型目录入库`
  - 上一份 §3.5 的全部
- iam：
  - `TestComponentManifest_不依赖authz族任何成员`（今天红：`component.yaml:26`）
  - `TestSignAccessToken_带typ_access与tenant_id`
- inventory：
  - `TestListBalances_只看到bundle授予的仓库`
  - `TestWarehouseAccessEndpoints_已删除答404`
  - finance 对称
- sales：
  - `TestCancelOrder_cancel档位own时取消同部门别人的订单Forbidden`
  - `TestListOrders_dept档位只看本部门`
  - `TestListOrders_投影里共享给我的角色的订单在view_visible里出现`（用 `besdktest.InsertACL`；今天红）
  - `TestConfirmOrder_看不见的订单答404`（Q3）
  - opportunity 对称
- workflow / notification：
  - `TestListTasks_all档等同旧admin视图`
  - `TestAdminRoute_旧admin键迁移后行为不变`
- be-acceptance：
  - `TestConformanceCore_原生成员全部通过`
  - `TestAuthzCapabilityScan_组件要求的能力未提供时报错`
  - `TestAuthzgenFresh_生成物过期报错`

**P1**：

- `TestShares_共享者没有该关系所含的键时403`
- `TestShares_写入后共享者自己立刻可见`（zookie）
- `TestShares_接收者带revision首个请求即可见`
- `TestShares_static成员答501带能力名`
- `TestMask_无成本字段键时standard_cost为null且在_masked里`
- `TestSort_按掩码字段排序被拒`
- `TestUpdate_改掩码字段答403`
- `TestE2E_List与Can一致_随机夹具`
- `TestNotification_收到共享事件给接收者发带rev的通知`

**P2–P3**：

- `TestDelegation_on_behalf期间B看到A的待办_到期后看不到`
- `TestAgentToken_天花板外的键403`
- `TestAgentToken_用户被撤角色后代理同时失权`
- `TestAgentToken_delegable为false的键不能进profile`
- `TestImpersonation_只读且每条访问日志带act`
- `TestConformanceGraph_openfga嵌套团队可见且ListObjects有上限`

---

## 8. 需要你拍板的点

只列业务口径和方向性的问题。技术选择本文已经给了推荐，不再问。

1. **共享能不能"顺带"给功能权限？** 例：一个**没有** `erp.sales.view` 的仓库同事，被共享了一张订单，他能不能打开？
   - 一种是协作优先（Google Docs、ERPNext 的做法）：viewer 共享自带"对这一条的查看权"。
   - 另一种是管控优先（Salesforce、Dynamics 的做法）：还得有角色给的 view 键，共享只放开行。
   
   推荐：**查看类可以顺带，动作类不行**。viewer 带 view；confirm、cancel、close 这类动作永远要角色键，editor 只能带"编辑草稿"这一级。由各组件在 `relations.grants` 里显式声明。
2. **谁可以共享？** 推荐：持有该类型的 share 键，并且自己对这条记录至少有要授出的那一级关系；不允许"转共享"超过自己的级别。备选是只有负责人（owner）能共享（Salesforce 默认）。
3. **R62 细化**：看不见的记录，对**命令**也答 404，而不是今天的 403，堵住"用命令探测一条记录是否存在"。推荐：改。代价：sales、workflow 各有 1–2 条测试要单独提交改名。
4. **AI agent 的边界**：agent 能不能做不可逆动作（确认订单、过账、发货）？推荐：
   - 默认 profile 只读 + 起草。
   - 不可逆动作的键标 `delegable: false`，由人在 workflow 里确认。
   - 共享、授权管理永远不能下放。
   
   要你定的是这份"永不下放"清单的口径。
5. **生产环境要不要"以他人身份查看"（扮演）？** 推荐：允许，但只读，要单独的键 `infra.authz.impersonate`，每次访问日志都带 `act`，并且通知被扮演的人。备选是只在开发环境开。
6. **openfga 成员什么时候建？** 推荐：不进 06，等 `prj/project` 开发时随需求建，或者在阶段 07 专门做一次"替换演示"。06 内只用 static 成员证明可替换性。备选是 06 内就建，作为契约的第二个真实实现，越早越能逼出契约里的偏差，代价是多一个基础服务和适配器。
