# 数据范围：空 `dept_path` 被当成"看全部"的 fail-open 风险——分析与修法提案

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 进行中）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准。

## 0. 结论

- **漏洞成立，而且比"根节点用户"宽得多。** authz 给出的真实部门路径恒为 `/<id>/…/`，根部门也是 `/<根id>/`，**从来不是空串**；`dept_path` 为空只有一种来源：**这个人没有被分到任何部门**（新用户的默认状态）。SDK 把这种状态解读成"不限"，所以"新开的账号、只被授了查看权限、还没分部门"的人看得到全部订单、全部商机、全部待办。
- **受影响的消费者只有 3 个，全部 Go**：`infra/workflow`（已发布 2.0.0）、`erp/sales`、`crm/opportunity`（都到 C6、未发布）。其余组件只用 `Owner`，不受影响。Python / TS SDK 有同样的求解代码，但目前没有任何组件用到它们的 `prefix`。
- **推荐方案 (a) 的"哨兵"形态**：be-sdk-go / python / ts 发 `v0.5.0`，`dept_path` 为空（或不以 `/` 开头）时 `Prefix`/`Exact` 取一个任何真实路径都不会以它开头的哨兵值、新增 `HasDept=false`；`"/"` 是整棵树的显式根标记（`All=true`，作为普通前缀天然匹配所有真实路径）。**对没改代码的消费者也是 fail-closed**（哨兵在 `LIKE … || '%'` 和 `strings.HasPrefix` 里都落空，OR 退化成"只剩本人"）。
- **需要协调的发布最少**：三个 SDK tag、`infra/workflow 2.0.1`、`infra/authz 2.0.1`（只改种子与文档：把 `dev.superuser` 分到根部门）、`config/vars.yaml` 一行。sales / opportunity / iam / bff 都还没发布，跟着这次改动走，版本仍是 2.0.0。不需要新权限键、不改契约、不做数据迁移、不需要用户重新登录。

## 1. 问题复述

`tools/be-sdk-go/scope.go:48-53`：

```go
return ScopeFilter{
	All:    claims.DeptPath == "",
	Prefix: claims.DeptPath,
	Exact:  claims.DeptPath,
	Owner:  claims.Sub,
}
```

真正造成放行的不是 `All`（全项目没有任何组件读 `.All`，见 §3），而是 `Prefix == ""`：

- SQL：`dept_path LIKE '' || '%'` 就是 `LIKE '%'`，匹配所有行；
- Go：`strings.HasPrefix(x, "")` 对任何 `x` 都为真。

于是 `owner OR org` 的 OR 判据退化成"全部"，"本部门及下级"视图（`view=dept`，sales / opportunity 的默认视图）也是"全部"。SDK 注释（`scope.go:20`）、三份 `docs/authz-protocol.md`（`tools/be-sdk-go/docs/authz-protocol.md:40,107,115`）、各组件注释都把它写成"坐在根节点，天然不限，不是特判"——但这个前提和 authz 的真实数据对不上（§2）。

这正好违反项目易错点表里的"Combine `owner` OR `org` with one operand left at 'match all'"一条，以及 0205 的"A security default must fail closed"。

## 2. `dept_path` 从哪来、什么时候为空（问题 1）

### 2.1 签发链路

1. `infra/authz` `ResolveClaims`：`backend/internal/service/service.go:91-101`，`deptPath` 来自 `repo.DeptPathFor`。
2. `DeptPathFor`：`backend/internal/repo/departments.go:97-113`，`user_departments JOIN departments`；**查不到行时返回空串，不是错误**（注释："还没有部门归属的用户是合法状态"）。测试 `repo_test.go:501` `TestDeptPathFor_未分配返回空串不报错` 锁定了这个行为。
3. 路径格式：`CreateDepartment`（`departments.go:24-56`）里 `parentPath` 初值是 `"/"`（第 30 行），`DeptPath = parentPath + id + "/"`（第 47 行）。所以**顶层部门是 `/<id>/`，子部门 `/<id>/<id>/`，任何已分配用户的 `dept_path` 都以 `/` 开头、以 `/` 结尾、非空**。迁移 `migrations/001_create_authz.up.sql:58` 的注释同样是 `"/1/12/"`。
4. `infra/iam-casdoor` 原样抄进应用 token：`backend/internal/service/service.go:183-195`（`DeptPath: resp.DeptPath`，第 194 行），`internal/tokens/tokens.go:36,71`。
5. 各 SDK 解析：Go `jwt.go:27,69`；Python `besdk/jwt_verify.py:64`（`payload.get("dept_path") or ""`）；TS `src/jwtVerify.ts:52`。**claim 缺失也落成空串。**

### 2.2 各种身份分别得到什么

| 身份 | `dept_path` | 今天的效果 | 依据 |
|---|---|---|---|
| 未分配部门的普通用户（新账号的默认状态） | `""` | **看全部**（fail-open） | `departments.go:106-108` |
| 分到根部门的人（总公司） | `/<根id>/` | 看根部门以下全部有部门的行，**不需要空串** | `departments.go:30,47` |
| 超级用户 / `BOOTSTRAP_ADMIN_SUB` | 没有任何地方给他们分部门 → `""` | 看全部（是"恰好没分部门"带来的，不是设计出来的特权） | `module/module.go:31`、`service.go:45` 只授角色 |
| 服务身份（`SystemClient`、gRPC 组件间调用） | 不经过 `ScopeOf`：gRPC 面不转发也不验 JWT | 由各组件自己决定；workflow 的 gRPC `ListTasks` 直接传空前缀给 repo 当"全部"（§3.3） | `infra/workflow/backend/internal/service/service.go:100-107` |
| token 缺 `dept_path` claim / 别的签发方 | `""` | 看全部 | §2.1 第 5 点 |
| 格式异常（不以 `/` 开头） | 原样 | 前缀语义不可预期 | 无校验 |

另外：`AssignUserDepartment`（`departments.go:79-95`）不写 `stale_since`，改部门要等下一次签发才生效，最长滞后 `APP_TOKEN_TTL_SECONDS`（默认 600 秒，`infra/iam-casdoor/component.yaml:49`）。没有"取消分配"和"删部门"的接口，所以"分过部门后又变回空"目前不会发生。

### 2.3 种子用户

来源：`docs/en/03-seed-data.md` 第 13–14 行、`components/infra/authz/scripts/seed.sh:112-178`。

| 用户 | 部门 | 角色里与 org 维相关的键 | 今天在 org 维看到 |
|---|---|---|---|
| `dev.superuser` | **无**（文档原文 "every permission, no department"；`seed.sh` 只授角色，第 52-57 行） | 全部 | 全部（靠漏洞） |
| `dev.sales.east` | 华东分部 `/<根>/<华东>/`（`seed.sh:168`） | `erp.sales.view`、`crm.opportunity.view`、`infra.workflow.task.view` | 华东 |
| `dev.warehouse.south` | 华南分部（`seed.sh:169`） | `infra.workflow.task.view` | 华南的待办 |
| `dev.finance.viewer` | **无**，刻意的（`seed.sh:170` 注释"财务视角本身是跨部门的"） | 只有 `erp.finance.view`（legal_entity 维，不读 dept_path） | 不涉及 |

种子部门树只有一个根："「本地测试」总公司"，华东、华南都挂在它下面（`seed.sh:112-114`）。

种子里已经存在 `dept_path = ''` 的业务行：`dev.superuser` 建的 `seed-order-1..3`（`components/erp/sales/scripts/seed.sh:70-76`）、`seed-opp-1..5`；`erp/sales` 补偿失败时开的异常待办 `AssigneeDeptPath: ""`（`components/erp/sales/backend/internal/tcc/confirm.go:252`）。

## 3. 全部消费者（问题 2）

搜索范围：`components/*/*` 全部后端（含已发布）、三个 SDK。`grep` 了 `ScopeOf` / `scope_of` / `scopeOf` / `.All` / `.Exact` / `ScopePrefix` / `LIKE … || '%'` / `HasPrefix`。

### 3.1 用到 org 维（`Prefix`）的——全部受影响

| 组件 | 状态 | 位置 | 判据 | 空 `dept_path` 今天的效果 |
|---|---|---|---|---|
| infra/workflow | **已发布 2.0.0** | `repo/tasks.go:72-73` `Task.InScope` | `HasPrefix(assignee_dept_path, prefix) OR assignee_sub = owner` | 任意一条待办详情可见（`service.go:111-122` `checkTaskInScope` → `GetTaskDetail`） |
| | | `repo/tasks.go:292-295` + `service.go:145-151` `ListMyTasks` | `assignee_sub = owner OR assignee_dept_path LIKE prefix \|\| '%'` | "我的待办"= 全租户所有待办 |
| | | `repo/tasks.go:287-291` + `service.go:157-161` `ListTasksAdmin` | 只判 `LIKE prefix \|\| '%'` | 管理视图 = 全部 |
| erp/sales | C6，未发布 | `repo/repo.go:43-44` `Order.InScope`；`service.go:25-35,146-159` | OR | 任意订单可看、可**确认/取消/发货**（`checkOrderInScope` 也护写路径） |
| | | `repo/order.go:196-205` + `service.go:161-169` `ListOrders` | `view=dept`（默认）只判 `LIKE` | 全部订单 |
| | | `repo/stats.go:66-68` + `service.go:173-182` `StatsSummary` | 同上 | 全公司的统计数 |
| | | `tcc/create.go:84-87` 建单快照 | `DeptPath: scope.Prefix`，`DeptID: leafDeptID(scope.Prefix)` | 写进 `dept_path = ''`（行本身只对 owner 可见，但对"空前缀"的人可见） |
| crm/opportunity | C6，未发布 | `repo/repo.go:37-38` `Opportunity.InScope`；`service.go:59-69,305-335` | OR | 任意商机可看、可改阶段 / 赢单 / 输单；阶段历史可看 |
| | | `repo/opportunity.go:195-202` + `service.go:350-358` `ListOpportunities` | `view=dept` 只判 `LIKE` | 全部商机 |
| | | `repo/funnel.go:36-38` + `service.go:339-348` `Funnel` | 同上 | 全公司漏斗 |
| | | `service.go:206-213` 建档快照 | 同 sales | 写进 `dept_path = ''` |

`assembly.yaml` 里声明 `org` 维的也正好是这三个：`erp/sales/assembly.yaml:17`、`crm/opportunity/assembly.yaml:20`、`infra/workflow/assembly.yaml:18`。

现有测试把漏洞写成了期望：`erp/sales/backend/internal/repo/scope_test.go:23` `{"根节点前缀天然命中全部", …, "", …, true}`、`crm/opportunity/backend/internal/repo/scope_test.go:21` 同构；be-sdk-go `scope_test.go:35-41` `TestScopeOf_部门树根节点自然得到All`，python `tests/test_scope.py:32`、ts `test/scope.test.ts:29` 同名用例。这些是"错的测试"，按铁律在**单独的提交**里改并写明原因。

### 3.2 只用 `Owner` 的——不受影响

| 组件 | 位置 |
|---|---|
| infra/authz（`/me/permissions`） | `backend/internal/http/http.go:82` |
| infra/iam-casdoor（logout） | `backend/internal/http/http.go:108` |
| infra/notification | `backend/internal/service/service.go:36,49,54` |
| erp/inventory（查 `warehouse_access`） | `backend/internal/service/service.go:28` |
| erp/finance（查 legal entity 授权） | `backend/internal/service/service.go:37`；`grpc/grpc.go:42` 只为触发 panic 检查 |
| infra/print（Python） | `backend/infra_print/http/routes.py:67` |

全项目没有任何组件读 `.All` 或 `.Exact`。mdm/customer、mdm/product、integration/im-dingtalk 不调 `ScopeOf`。infra/bff-mobile 原样转发 Authorization 给下游 REST（`src/clients/restForward.ts:4`），自己 `data_scopes: none`，只透传 `dept_path` 字段做展示（`src/resolvers/order.ts:69`、`opportunity.ts:72`、`task.ts:49`）。

### 3.3 SDK 与相邻发现

- Python：`besdk/authz.py:150-157` 内联 `all=claims.dept_path == ""`、`prefix=claims.dept_path`；TS：`src/authz.ts:206-212` 同构。求解逻辑写在判定链中间，`scope.py` / `scope.ts` 的测试只测了 setter/getter，没有测"从 claims 怎么算"。
- workflow 的 repo 层自己也有一条"空前缀 = 全部"的约定，给 gRPC 系统调用用：`service.go:104-106` 把 `AdminView=true`、`ScopePrefix` 留空传下去，`repo/tasks.go:216-220,253-255` 注释写明。SDK 修好之后 REST 路径不会再给 repo 空串，但 repo 里"空串就是全部"这个魔法值还在，下一个调用方漏填就又放开了。应改成显式参数。
- 小问题，不在主线：Python `jwt_verify.py:58`（`require: ["sub","iat"]`）和 TS `jwtVerify.ts:47`（`requiredClaims`）只要求 claim **存在**，`sub: ""` 能通过；Go `jwt.go:61` 拒绝空 `sub`。iam 只会签真实 sub，风险低，可以在这次 SDK 发版里顺手对齐。
- `LIKE` 的通配符：真实路径只有数字和 `/`，不受 `_`/`%` 影响；哨兵值要避开这两个字符（见 §5.1）。

## 4. 有没有正当的"空 dept_path = 看全部"需求（问题 3）

没有。逐条对照：

1. **根节点 / 总公司的人**：分到根部门，得到 `/<根id>/`，前缀已经覆盖整棵树。空串从来不是根节点的表示（§2.1 第 3 点）。
2. **多个顶层部门（多棵树）**：authz 允许多个 `parent_id IS NULL`。要跨树看全部，需要一个比 `/<id>/` 更短的公共前缀——`"/"` 正好是所有真实路径的前缀，可以作为显式根标记，不需要空串。目前种子只有一棵树，authz 也还没有签发 `"/"` 的入口；那张部门表本来就是临时的（`departments.go:1-3`，迁移注释说由组织主数据组件接管），可以留到那时再给。
3. **跨部门的职能角色**（财务、审计）：它们看的数据用别的维度（finance 的 `legal_entity`），不读 `dept_path`。`dev.finance.viewer` 不分部门是对的，修完也不受影响。
4. **超级用户 / 首个管理员**：现在看全部是"恰好没分部门"的副作用。项目模型里"看全公司"是身份（坐在哪个部门），不是特权开关；给他分到根部门即可。
5. **服务身份**：不经过 `ScopeOf`（§2.2），与 token 里的空串无关。

对照项目规则：

- `docs/en/01-conventions/02-backend.md` 的 Data scopes 一节："`org` (prefix match on `dept_path`, no copy of the org tree)"；"When a list combines `owner` and `org` with OR, both operands must come from the caller's real scope; one operand left at 'match all' makes the whole condition match everything"。空串不是"真实范围"，是"没有范围"。
- 0205：行可见性跟着版本走，"A security default must fail closed"；明确排除"A runtime toggle such as 'let department A see department B's orders'"。
- 0206：`org` 维就是物化路径前缀，不复制组织树、不递归查询。根部门前缀或 `"/"` 都在这个模型之内；空串表示"看全部"是模型外的特例。
- 先例：workflow 的 `infra.workflow.admin`（`http/http.go:32`）是"用权限键切换视角"——**只绕过 owner 维、不绕过 org 维**（`service.go:153-161`）。项目已经选了"权限键决定能做什么，org 维始终由身份限定"。

## 5. 方案（问题 4）

### 5.1 方案 (a)：SDK 让空路径"只剩本人"，`"/"` 是显式根标记（推荐，用哨兵实现）

**语义**

| token 里的 `dept_path` | `HasDept` | `All` | `Prefix` / `Exact` | 效果 |
|---|---|---|---|---|
| `""` 或不以 `/` 开头 | false | false | 哨兵 `besdk.NoDeptPath`（如 `"!no-dept"`：不以 `/` 开头、不含 `%` `_` `\`） | org 维什么都不命中；OR 判据只剩 owner；`view=dept` 为空列表 |
| `"/"` | true | true | `"/"` | 作为普通前缀匹配所有真实路径（不匹配 `dept_path = ''` 的行） |
| `/1/12/` | true | false | 原值 | 不变 |

**为什么用哨兵，而不是只加一个 `HasDept` 让组件自己判断**：只加字段的话，没改代码的消费者照旧拿到 `Prefix == ""`，仍然是 fail-open。哨兵是值层面的修法：

- 现有的 `LIKE $n || '%'` 与 `strings.HasPrefix` 不改一行就落空，**已发布组件、以及在外壳里被 MVS 抬到新 SDK 的旧成员代码，都自动 fail-closed**；
- 外壳的 `go.mod` 只会选成员里最高的 SDK 版本。只要一个成员钉了 v0.5.0，同壳的其它成员也跟着用 v0.5.0。所以新 SDK 对只用 `Owner` 的消费者必须完全兼容——哨兵方案满足（`Owner` 不变）。

哨兵唯一的风险是被**写进行里**：sales / opportunity 建单时把 `scope.Prefix` 当快照写进 `dept_path`，还会用 `leafDeptID` 算出 `dept_id`。这两个组件都还没发布，这次一起改成"`HasDept` 为假时写空串"。已发布组件里没有把 `Prefix` 写进行的（workflow 的 `assignee_dept_path` 由调用方经 gRPC 传入）。

**各仓库的改动**

- **be-sdk-go → v0.5.0**（在 0.x 里，导出字段语义变了，按 minor 升）
  - `scope.go`：新增 `const NoDeptPath`、字段 `HasDept bool`；`ScopeOf` 按上表求解；改第 5-25、32-41 行的注释（"空字符串表示不限"整段作废，改成"SDK 保证 `Prefix` 永不为空；repo 收到空串必须当成编程错误"）。
  - `scope_test.go`：第 35-41 行旧用例单独一个提交改掉（说明它锁定的是 fail-open）；新增红测试，见 §6.2。
  - `docs/authz-protocol.md:40,107,115`、`README.md:139`：改写空串语义。三个 SDK 的 `authz-protocol.md` 同步改（项目记忆：三份是同步维护的）。
- **be-sdk-python → v0.5.0**：把 `authz.py:150-157` 的内联求解提成 `scope.py` 里的纯函数 `scope_from_claims(claims)`，加 `has_dept`、`NO_DEPT_PATH`；`tests/test_scope.py:32` 旧用例单独提交改掉；顺手让空 `sub` 被拒（§3.3）。
- **be-sdk-ts → v0.5.0**：同上，`scopeFromClaims`，`ScopeFilter` 加 `hasDept`；`test/scope.test.ts:29` 旧用例单独提交改掉；空 `sub` 被拒。
- **infra/workflow → 2.0.1**（已发布，补丁版本；proto 不动，`gen/infra/workflow` 不打新 tag）
  - `go.mod` 升到 be-sdk-go v0.5.0。
  - `repo/tasks.go`：`ListInput` 加显式 `AllDepts bool`，只有 gRPC 的 `Service.ListTasks`（`service.go:104-106`）设为 true；`AllDepts=false` 且 `ScopePrefix == ""` 时返回 `ErrInvalidArgument`，不再当作"全部"。`Task.InScope`（第 72-73 行）在 `scopePrefix == ""` 时 org 一侧直接为假。改第 66-71、210-220、253-255 行注释。
  - `docs/design.md:109-111` 与 `design.zh.md` 对应行：删掉"`dept_path` 为空的调用者坐在根节点、看得到全部"，改成"没有部门的调用者只看得到指派给自己的待办"。
  - 下游：`erp/sales`、`infra/bff-mobile` 的 `component.yaml` 把 `infra/workflow@2.0.0` 改成 `@2.0.1`（两个都未发布）；`brickkit upgrade infra/workflow`。
- **infra/authz → 2.0.1**（只改种子与文档，代码不动）
  - `scripts/seed.sh`：`assign_dept "$SEED_SUB" "$ROOT_DEPT_ID"`，把 `dev.superuser` 分到"「本地测试」总公司"。
  - `docs/design.md`（+zh）、`BRICKKIT.md`（+zh）"部署前准备"：写明"未分配部门的人看不到任何按部门限定的行，只剩本人的；看全公司就分到根部门"。`authz.proto:48` 的注释（"未分配部门时为空串"）仍然成立，**不改**，避免契约包重新生成。
  - 不加签发 `"/"` 的入口，留给组织主数据组件（§4 第 2 点）。
  - 连带：`config/vars.yaml:22` `AUTHZ_BUNDLE_URL` 改成 `infra-authz-2-0-1`；`infra/iam-casdoor/component.yaml` 的 `infra/authz@2.0.0` 改成 `@2.0.1`（iam 未发布）。`make gates` 的 `service-hostname-scan` 会盯这一项。
- **infra/iam-casdoor（未发布，仍是 2.0.0）**：代码不动（原样抄 `dept_path` 是对的）；`go.mod` 升 v0.5.0（让 go-infra 外壳里各成员的 SDK 一致），依赖 pin 改成 authz@2.0.1。
- **erp/sales（未发布，仍是 2.0.0）**
  - `go.mod` v0.5.0；依赖 `infra/workflow@2.0.1`。
  - `tcc/create.go:84-87`：快照 `DeptPath`/`DeptID` 在 `!scope.HasDept` 时写空串（不能写哨兵）。`opportunity_won.go:177` 取自事件，不动。
  - 纵深防御：`repo/repo.go:43-44` `InScope` 在 `scopePrefix == ""` 时 org 一侧为假；`repo/order.go:200-204`、`repo/stats.go:66` 在 `!ViewMine && ScopePrefix == ""` 时返回 `ErrInvalidArgument`。
  - 改注释：`repo/order.go:201-202`、`repo/repo.go:39-41`、`tcc/create.go:16-17`；`docs/design.md:130`（+zh）。
  - `repo/scope_test.go:23` 旧用例单独提交改掉。
- **crm/opportunity（未发布，仍是 2.0.0）**：与 sales 对称。`service.go:206-213` 快照；`repo/repo.go:37-38`、`repo/opportunity.go:199-202`、`repo/funnel.go:36`；`docs/design.md:142`（+zh）；`repo/scope_test.go:21` 单独提交改掉。
- **infra/bff-mobile（未发布）**：`package.json` 的 be-sdk-ts 升 v0.5.0；依赖 pin 改成 workflow@2.0.1。代码不动。
- **不需要动的已发布组件**：customer、product、notification、im-dingtalk、print、inventory、finance。它们只用 `Owner`，或者根本不调 `ScopeOf`；进外壳时被抬到 v0.5.0 也不会改变行为。print 继续钉 be-sdk-python v0.4.4，py-render 外壳跟着它。
- **项目正式文档**（中英各一份）：`docs/en/01-conventions/02-backend.md` Data scopes 一节加一条："A caller without a department (`dept_path` empty) matches no `org` row; only the `owner` dimension still applies. Seeing the whole organisation means sitting in its root department."；`docs/en/03-seed-data.md` 第 13 行 `dev.superuser` 的描述改成"head office"，第 23 行补一句"没有部门的人在部门视图里是空列表"。是否给根 `AGENTS.md` 的易错点表加一行（"把空 `dept_path` 当成根节点"），由控制者决定。

**对 token 和数据的影响**

- token 格式不变，不需要重新登录。修好的组件一上线，所有 `dept_path = ""` 的 token 立刻失去 org 维可见性（这正是要的效果）。`dev.superuser` 分到根部门以后，要等下一次签发才拿到 `/<根>/`（种子脚本每次都 `get_app_jwt` 现换，浏览器最多 600 秒）。
- 已有的 `dept_path = ''` 行（§2.3）修完后只对 owner 可见，**根部门的人也看不到**（`'' LIKE '/<根>/%'` 为假）。演示库：种子按固定幂等键复用旧行，所以重灌之前要先清——`make -C components/crm/opportunity seed-clean && make -C components/erp/sales seed-clean`（或者两者 `db-reset`），再按 T25 第 3 步重灌，`dev.superuser` 的单据就会带上 `/<根>/`。生产环境还没有数据。不建议做回填：快照语义下没法知道当时"应该"属于哪个部门。
- sales 补偿失败时开的异常待办（`confirm.go:252`，`AssigneeDeptPath: ""`）修完后只有被指派人能看到；管理视图（只判 org）看不到。被指派人能看到就够处理了，这个影响可以接受。要不要给 sales 配一个异常处理部门，另开一条。

### 5.2 方案 (b)：SDK 遇到空路径直接拒绝（403 / 不返回任何行）

- **在 `ScopeOf` / `RequirePermission` 里拒绝**：会把只用 `Owner` 的组件一起拒掉。没有部门的人会被挡在 finance（`dev.finance.viewer` 刻意不分部门）、notification、print 外面；首个管理员（`BOOTSTRAP_ADMIN_SUB`，没有部门）调不了 `/me/permissions`（`authz/http.go:82`），授权流程起步不了；iam logout 也会失败。没有部门的被指派人还会看不到指派给自己的待办（sales 的异常待办）。不可接受。
- **只在 org 维拒绝**：Go 结构体字段没法在被读取时报错，只能把 `Prefix` 换成 `OrgPrefix() (string, error)` 之类的方法，等于改 API。这样**所有** org 消费者都要改代码；没改的会编译不过，这一点算安全，但已发布的 workflow 照样要发版。和 (a) 比，只多出"no-dept 用户的 OR 判据里连本人的行也看不到"这一个差别——而这个差别正是要避免的。
- 发布：三个 SDK 都是破坏性 API 变更（v0.5.0），workflow 2.0.1，authz 2.0.1（种子）。至少和 (a) 一样多，但语义更差。**不推荐。**

### 5.3 方案 (c)：用单独的权限键表示"跨部门可见"（如 `erp.sales.view_all_depts`）

- **它本身补不上漏洞**：空串照样是"全部"，必须再配一个 (a) 或 (b)。(c) 只是在 (a) 之上，给"看全公司"换一种授予方式。
- 要改的东西：三个 SDK 都新增 `HasPermission(ctx, key)`（今天的 be-sdk-go 没有，导出函数只有 `RequirePermission` / `ScopeOf` / `ContextWithClaims`，见 `authz.go:37-137`）；sales、opportunity、workflow 各加新键，追加进 `registry/permissions.tsv`（只增不改，加了就永远在）和 `assembly.yaml`；重新生成 `brickkit.yaml` 里 authz 的 `permissionCatalog` 那一行（项目记忆：漏掉这步，新键永远进不了 permissions 表）；authz 种子给角色授新键；service 层按键分支；06c 前端加菜单 / 按钮判断。
- **和决策冲突**：0205 排除"A runtime toggle such as 'let department A see department B's orders'"。管理员运行时给一个角色授"看全部部门"，就是一个运行时的行可见性开关。要走这条路，得先另写决策推翻或细化 0205。workflow 的先例（`infra.workflow.admin` 不绕过 org 维）也是反方向。
- 发布：SDK×3、workflow 2.0.1、authz 2.0.1，sales、opportunity 加键，外加一条新决策。**现在不做。** 真的出现"审计员要跨所有部门看"的需求时，先用"分到根部门"满足它；只有"同一个人既要按本部门做事、又要看全公司"这种身份表达不了的情况，才回来考虑 (c)。

### 5.4 对比

| | (a) 哨兵 + `"/"` | (b) 拒绝 | (c) 权限键 |
|---|---|---|---|
| 没改代码的消费者是否 fail-closed | **是**（值层面） | 只在 org 维版本下"编译不过"才算是 | 否（必须配 (a)/(b)） |
| 没有部门的人还看得到自己的行 | 是 | 否 | 取决于配哪个 |
| 只用 Owner 的组件 | 不受影响 | 受影响（只在 ScopeOf 拒绝时） | 不受影响 |
| 需要的发布 | SDK×3、workflow 2.0.1、authz 2.0.1（只改种子） | 同左，且 API 破坏 | 同左 + 新键 + 新决策 |
| 合同 / 迁移 | 都不需要 | 都不需要 | 新增权限键 |
| 与 0205/0206 | 一致 | 一致 | 与 0205 冲突 |

## 6. 推荐与落地顺序（问题 5）

### 6.1 推荐

选 **(a) 的哨兵形态**。理由：只有它在值层面 fail-closed，连没改代码的已发布组件、外壳里被抬高 SDK 的旧成员都能自动收紧。只用 Owner 的组件一个都不用动。已发布组件里只有 workflow 要发补丁。sales、opportunity、iam、bff 都在 C6 之后、发布之前，正好跟这次一起走。authz 只为种子发一个补丁版本，而且要赶在 iam 发布、go-infra 外壳（T22）组装之前，这样 iam 的 pin 和外壳都只需要定一次。

### 6.2 顺序（贴合 06b 现状：W1 九个已发布；sales / opportunity / iam / bff 到 C6 未发布；外壳 T21–T24 未开始）

1. **SDK 三条线并行**（各自仓库内提交；tag / 推送留给控制者）
   - 先写红测试，在 v0.4.0 上跑红：
     - Go `TestScopeOf_dept_path为空时org维落空只剩本人`：`Claims{Sub:"u_x", DeptPath:""}` → `!All`、`!HasDept`、`Prefix == NoDeptPath`、`Exact == NoDeptPath`、`Owner == "u_x"`；`strings.HasPrefix("/1/12/", f.Prefix)` 为假，`strings.HasPrefix("", f.Prefix)` 也为假。
     - Go `TestScopeOf_斜杠是整棵树的显式根标记`：`"/"` → `All && HasDept && Prefix == "/"`，`HasPrefix("/1/12/", "/")` 为真。
     - Go `TestScopeOf_不以斜杠开头的dept_path按无部门处理`：`"1/12/"` → 同无部门。
     - Go `TestNoDeptPath_不以斜杠开头且不含LIKE通配符`。
     - Python / TS：对应的 `scope_from_claims` / `scopeFromClaims` 四条，加"空 sub 被拒"一条。
   - 旧用例（Go `scope_test.go:35`、py `test_scope.py:32`、ts `scope.test.ts:29`）各自单独提交改掉，提交说明写"它锁定的是 fail-open"。
   - 实现 → 跑绿 → 改注释、README、三份 `authz-protocol.md`。控制者打 `v0.5.0` 并推送（Go 记得 proxy 负缓存：推送前别 `go get` 这个版本）。
2. **infra/workflow 2.0.1**（version-bump-ship 全流程）
   - 红测试（真 PG，`brickkit_test_db`），先在 SDK v0.4.0 上跑红：
     - `TestListMyTasks_无部门的人只看到指派给自己的待办`：建三条待办（指派给我、`/9/99/` 的别人、`assignee_dept_path=''` 的别人），用 `authedCtx(me, "")` 调，结果只有第一条。
     - `TestListTasksAdmin_无部门的管理员看不到任何部门的待办`。
     - `TestGetTaskDetail_无部门的人看别人的待办是Forbidden`。
     - repo：`TestListTasks_非系统视图ScopePrefix留空报InvalidArgument`、`TestTask_InScope_空前缀org一侧不命中`。
     - 回归：`TestListTasks_gRPC系统视图AllDepts仍看全部`。
   - 升 SDK → service 测试转绿；改 repo（`AllDepts`）→ repo 测试转绿；改文档；`make ship`；`brickkit upgrade infra/workflow`。
3. **infra/authz 2.0.1**（可与第 2 步并行）：种子 + 文档；`make ship`；`brickkit upgrade infra/authz`；同一批改 `config/vars.yaml:22`；`make gates`（`service-hostname-scan` 零警告）。
4. **erp/sales、crm/opportunity**（各自补 C 步，不发版号，仍是 2.0.0）
   - 红测试（真 PG）：
     - sales：`TestListOrders_无部门的人dept视图看不到任何订单`、`TestStatsSummary_无部门的人dept视图为零`、`TestGetOrder_无部门的人看别人的订单是Forbidden`、`TestConfirmOrder_无部门的人确认别人的订单是Forbidden`、`TestCreateOrder_无部门的人建单dept_path与dept_id留空不写哨兵`、`TestListOrders_根标记斜杠看得到所有有部门的订单`、repo `TestListOrders_dept视图ScopePrefix留空报InvalidArgument`。
     - opportunity：对称的 List / Funnel / Get / StageHistory（看不到的答 404）/ MarkWon（Forbidden）/ Create 快照，加 repo 守卫。
   - 旧用例 `scope_test.go` 单独提交改掉；升 SDK、pin workflow@2.0.1；改快照与守卫；改文档；重跑各自 C1–C6 的测试与 `make verify`，结果追加进 `dev/test-records/06b/erp-sales.md`、`crm-opportunity.md`，然后照原计划走 T18 / T19 发布。
5. **infra/iam-casdoor、infra/bff-mobile**：只改 pin（SDK v0.5.0；iam → authz@2.0.1；bff → workflow@2.0.1），重跑测试，照原计划走 T17 / T20。
6. **项目正式文档**：`02-backend.md` Data scopes 一节、`03-seed-data.md`（中英镜像，`make docs-mirror`、`make docs-boundary`）。
7. **外壳 T22–T24**：`go.mod` 钉 be-sdk-go v0.5.0（成员中的最高版本）。审查时核对 inventory、finance、customer、product、notification、im-dingtalk、authz 这些 2.0.0 成员在 v0.5.0 下的行为不变（它们只用 Owner，§3.2）。`dependency-version-scan` 不看 SDK 版本（`dependencyversionscan.go:172`），这一项只能靠人工核对。
8. **T25 加三项核对**（锁内）
   - 重灌前先清 sales / opportunity 的种子（§5.1"对数据的影响"）。
   - `dev.superuser` 不带 `view` 参数打 `GET /erp/sales/orders`，看得到 `dev.sales.east` 的订单：证明根部门前缀端到端可用，种子已经不再依赖漏洞。
   - 负向：临时建一个只授 `erp.sales.view`、不分部门的用户，`GET /erp/sales/orders` 返回空列表，`GET /erp/sales/orders/<别人的订单>` 返回 403。用完删掉，结果原文写进 `integration.md`。

### 6.3 可选加固（交 T26 判断）

- be-acceptance 的 `datascopetestscan`：声明了 `dimension: org` 的组件，必须有一条名字里含"无部门"或"no dept"的测试。只是启发式，但能挡住下一个 org 维组件重犯。
- 06c 前端：没有部门的用户在部门视图里看到的是空列表，最好提示"尚未分配部门，请联系管理员"。数据从哪来（例如 `/api/me` 返回 `dept_path` 是否为空）到 06c 再定。

## 7. 需要拍板的点

1. 哨兵的具体取值（建议 `"!no-dept"`）以及是否导出成常量。导出的好处是组件测试能直接断言。
2. authz 2.0.1 现在发，还是推到 T26。推到 T26 的话，`dev.superuser` 在部门视图里一直是空的，T25 第 5 步要改成 `view=mine`，而且 iam 和 go-infra 外壳都要重新 pin 一次。建议现在发。
3. 没有部门的人还能不能建单 / 建商机。本提案是"能建，行只对本人可见"。另一种做法是返回 `FailedPrecondition`："未分配部门不能建单"。这属于业务规则，sales / opportunity 未发布，现在定成本最低。
4. 要不要在根 `AGENTS.md` 的易错点表里加"把空 `dept_path` 当成根节点"一行。
