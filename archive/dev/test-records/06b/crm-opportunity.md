# 06b crm/opportunity：过程记录

> 本工作线中途接管：上一位实现者在 C4 中途被打断（已提交到 accc8d3，另有 4 个未提交文件，没有留下记录与报告）。本记录从接管时起写；接管之前的 C1–C4 步骤按它留在 scratch 里的日志（`$S` = `$BE_SCRATCH/06b/crm-opportunity/`）与提交说明整理，原始终端输出已不可得。本次只做 C1–C6，C7 起等控制者确认。

## 概况

- 日期：2026-10-02
- brickKit：`BrickKit CLI v1.1.0`
- SDK：be-sdk-go v0.5.0（C1–C6 时是 v0.4.0，R60 起 v0.5.0）
- 基础资源：接管时没有项目容器、没有项目锁、本地模式关；`make test-db-init` 与 `make gates` 都能连上 be-postgres / NATS
- 组件与版本：crm/opportunity 1.0.13 → 2.0.0（组件仓库 34 个未推送提交，HEAD 255a87a；C6 结束时是 20 个、HEAD 9212623；tag 未打：2.0.0 / v2.0.0 / gen/crm/opportunity/v1.0.0 留给控制者）
- 交接给控制者的内容：见各轮的"小结"；最后一轮是"发布前修复（复审 I1 / I3 / M6）"

## crm/opportunity

### 目标

本组件按 component-loop 重建到 2.0.0；补 frontend-needs §2.6 的 `Opportunity.order_id`、`GET /opportunities/{id}/stage-history`、`GET /opportunities/funnel`，以及 P9 的 `sales.order.created.v1` 回填消费者；按接管后的裁定核对 NaN 类、R49、R51。

### 环境

brickKit v1.1.0，部署目标 docker；本 Task 只到 C6，没有起任何组件容器、没有改 local 模式。上游 mdm/customer、mdm/product 均已发布 2.0.0（见 C1 复核）。测试库 `brickkit_test_db`（`TEST_PG_DSN` 由 env.sh 拼出，不打印值），NATS `nats://localhost:4222`。

### 步骤

**接管前（按 scratch 日志与提交整理）**

- C1–C3：feaedfa `chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）`。`$S/lint-c3.log`：`🔎 Only crm/opportunity is checked …`、`✅ components/crm/opportunity/component.yaml`、`📋 Checked 2 files: 0 with errors, 70 warnings`（全部是 DOC_* 骨架警告，没有 MANIFEST_INVALID）。
- C4 机械迁移：`$S/go-v2.log` 第一次 `❌ go-v2.sh：1 条判据 FAIL`，`$S/go-v2-2.log` 起通过；形态 B 拆出嵌套契约包，📌 `gen/crm/opportunity/v1.0.0`。
- C4 审查与补接口：403f2a4（write.go 506 → 400 行，`runCommand` 事务骨架）、d2f7888（BatchGet 缺一个 id 整批失败）、8463824（加权金额与小计按十进制）、fe74de9（主数据调用 3 秒超时）、7b59c83（先写设计）、8cd7eea（`order_id` 迁移 004 + 契约 + 回填消费者，红：`$S/red-order.log` 四条 FAIL，例如 `order_test.go:145: 期望 order_id=…，实际 ""`）、5849f6e（R51）、accc8d3（stage-history，迁移 005）。

**接管后**

- 接管核对：`git status` 有 `M backend/internal/service/service.go`、`M migrations/embed.go`、`?? backend/internal/repo/funnel.go`、`?? backend/internal/service/funnel_test.go`。读过：funnel 的 repo / service / L2 测试已写完（视角与 List 同一个切换，两个操作数都来自 token；空 `dept_path` 按 SDK 定义是 All），`embed.go` 只是注释更新，全部保留。基线 `go test ./... -race` 全部 ok，2 条 SKIP（跨组件）。
- funnel RED 补证据：把 `repo.Funnel` 临时换成空桩跑 `TestFunnel`：
  `funnel_test.go:106: alice mine：每个阶段都要列出（5 个），实际 0`；恢复后 PASS。
- 4.6 人工部分：4e38cfe（`migrations/embed.go` 注释）。
- funnel REST + 路由冲突 L4（67cd265）：`routes_test.go` 用生产的 `RegisterRoutes` 造真实 Gin engine，在前面挂全局中间件记 `c.FullPath()`（没有 authz 时权限中间件一律 403，但匹配到哪条路由仍可判断）。红：
  `routes_test.go:42: GET /crm/opportunity/opportunities/funnel：期望匹配 /crm/opportunity/opportunities/funnel，实际 "/crm/opportunity/opportunities/:id"（状态 403）`；绿：funnel 打到 funnel，`/123` 打到 `:id`，`/123/stage-history` 打到历史。REST 形状测试：五个字段齐，`mine` 1 条 / `dept`、省略 2 条。
- NaN 类（dc297bf）：`expected_amount` 此前完全不校验。红（`$S/red-decimal.log`，28 处）节选：
  `validate_test.go:47: expected_amount=NaN：期望 ErrInvalidArgument，实际 err=<nil>，写进库的商机：expected_amount=NaN`
  `validate_test.go:47: expected_amount=1e3：… err=<nil>，写进库的商机：expected_amount=1000.00`
  `validate_test.go:47: expected_amount=100.005：… err=<nil>，写进库的商机：expected_amount=100.01`
  `validate_test.go:52: qty=0：… err=写 opportunity_items …: violates check constraint "opportunity_items_qty_positive" (SQLSTATE 23514)`
  `validate_test.go:63: probability=101：… violates check constraint "opportunities_probability_range"`
  `validate_test.go:98: 非法金额不该改库：原 10000.00 v1，现 NaN v2`
  `service validate_test.go:40: expected_amount=NaN：期望不调依赖、直接 ErrInvalidArgument，实际 校验客户失败: 拨号 mdm/customer: … 地址未注入`（service 侧的红是把 service 里的校验临时去掉跑出来的）。
  红阶段把 Update 测试收紧了一处：版本冲突也包着 `ErrInvalidArgument`，第一次误写入之后其余用例会被版本冲突"碰巧"判对，所以加了 `!errors.Is(err, ErrVersionConflict)`——测试还没绿过，不属于"改测试迎合实现"。绿：全部包通过。
- R49（b4ed426）：契约原来没有声明任何 409；PATCH 版本过期一直映射 Aborted。OpenAPI 只增声明 `409`，加 REST 测试（一写就绿，行为没变）；日志级别是 INFO。
- 4.7 Makefile / Dockerfile（68a1a84）：接管时 Makefile 还是 1.x 的（`DATABASE_*`、`deployment.image` 判据、`/tmp` 探针、§ 引用 20 处），按 mdm/customer 模板重写；`dag-check` 改成 yaml 解析，三种违规各自报（实测三个反例都 `✗` 退出 2）。Dockerfile 照模板，删 `COPY migrations`。
- REST 列表窗口（19ec32e）：OpenAPI 声明了 `created_after` / `created_before`，gRPC 读，REST handler 从来不读。红：`list_test.go:38 created_after=300 天前：期望 200 且列出 1 条，实际 200、0 条`；绿：默认窗口看不到 200 天前的商机，窗口内外各对，格式错 400。
- 历史引用清理（17f5c1d）：component-check 第 4 项 88 处（Makefile 20 处已随模板消失）；代码注释、OpenAPI / 事件清单说明、go.mod、buf.yaml、种子脚本改成原因本身。`.proto`、迁移 SQL 不动（R41）。`go-v2.sh --recheck` 全部 PASS，`buf breaking --against '.git#tag=v1.0.13'` 通过。
- E2（e2f0098）：`TestConsumer_客户事件维护展示快照` 经生产 `Start` 向生产 subject 发布，改成测试私有 subject，断言不变，连跑三次 ok。
- f1c2106：gofmt 两个测试文件（纯格式）。
- C5 文档（fe3236e）：八份写满；`docs/design.md` 补本轮结论，`design.zh.md` 逐节对译。
- 9212623：`.gitignore` 与模板一致。
- 4.18 / 5.2 / 6.4 `component-check.sh`：
  ```
  ✅ component-check crm/opportunity：10 项全部 PASS
  ```
  （C4 结束时那次：`❌ 3 项 FAIL`——4.5 的 `Makefile:36 DATABASE_*`、历史引用 88 处、占位符；前两项已修，占位符 C5 填掉。）没有 `history_allow`。
- 6.2 `make docs-check ID=crm/opportunity`：
  ```
  🔎 Only crm/opportunity is checked (brickkit lint --all checks the whole project)
  ✅ components/crm/opportunity/component.yaml
  ✅ components/crm/opportunity/ (docs)
  ℹ️ crm/opportunity is not in brickkit.yaml yet, so it has no configuration to check (brickkit add --local adds it)

  📋 Checked 2 files: 0 with errors, 0 warnings
  exit=0
  ```
  `make docs-boundary` exit=0。
- 6.3 `make check-version test contract-check import-scan module-check dag-check` exit=0：
  ```
  ✓ version=2.0.0（go.mod 主版本一致；HEAD 上没有 tag，或 2.0.0 与 v2.0.0 都在）
  ok  …/backend/internal/client / consumer / http / partition / repo / service
  buf breaking --against '.git#tag=v1.0.13'
  ✓ 无组件间 import
  ✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规
  ✓ 依赖 mdm/customer@2.0.0、mdm/product@2.0.0，无 ERP 同步边，无自环
  ```
  `go test ./... -race -count=1 -v`：50 个 PASS，0 FAIL，2 个 SKIP——`TestCreateOpportunity_真实校验客户与产品并取展示快照`、`TestCreateOpportunity_真实客户不存在时拒绝`（需要 `MDM_*_GRPC_ENDPOINT`，C7 由 `make verify` 的跨组件测试跑）。
- 4.16 `make -C $ROOT test-db-init ID=crm/opportunity` exit=0：`- crm/opportunity` → 两次 `迁移结束 … "version":5,"dirty":false` → `✓ 迁移幂等` → `✓ brickkit_test_db 就绪`。
- 6.5 `project-lock.sh -- make gates` exit=0（`$S/gates.log`）：九个门禁都 `0 条违规`；本组件不在任何 `✗` / `⚠` 行。别的组件的提示：`⚠ config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里`；`⚠ components/frontend/standard/component.yaml（组件还在 1.x…）：gatewayBaseUrl / iamIssuerUrl / casdoorClientId naming`。发布前两个门禁按 ship 写法自查（锁内）：`✓ config-key-scan（只看 components/crm/opportunity）：0 条违规`、`✓ openapi-additive-scan（只看 components/crm/opportunity）：0 条违规（0 条跳过提示）`，都 exit=0。
- `migrate-manifest.py crm/opportunity --check`：`✅ --check 全部为"无"`，exit=0。
- C1 "上游已发布"复核：`mdm/customer: refs/tags/2.0.0 refs/tags/v2.0.0`；`mdm/product: refs/tags/2.0.0 refs/tags/v2.0.0`。

### 现象

- 符合预期的：Gin v1.12 下静态段 `/opportunities/funnel` 与 `/opportunities/:id` 同层注册不冲突、静态段优先；funnel 的 SQL 合计与 Go 侧逐条四舍五入一致（`100.05 × 10% → 10.01`）；P9 消费者的重复投递、旧版本晚到、不同订单不覆盖都有真实 NATS + PG 测试。
- 不符合预期的（都已修，各有红测试）：`expected_amount` 不校验，`NaN` 真的落库；REST 列表不读契约声明的时间窗口参数；接管时 Makefile 仍是 1.x 模板（C4 4.7 未做）；客户事件消费者测试仍用生产 subject。

### 卡点与绕过

- 没有翻 brickKit 源码。读了 be-sdk-go v0.4.0 的 `authz.go`（确认没有测试用的 authz 注入口，所以路由测试改用 `c.FullPath()`）、`scope.go`（空 `dept_path` = All）、`query.go`（`ListWindow` 默认 90 天）、`endpoint.go`（`MDM_CUSTOMER_GRPC_ENDPOINT` 的命名），以及 be-acceptance 的 `gates/bareginscan.go`（确认 `_test.go` 不扫）。
- component-check 的历史正则 `阶段 ?[一二三四五六](?![条个次项份种步轮])` 把"每个阶段一行"判成"阶段一"：本组件的业务词就是"阶段"。改写成"每个阶段占一行"，没有用 `history_allow`。

### V 项

- 本 Task 只到 C6，没有 V 项实测。

### 结论

C1–C6 完成，全部判据通过；C7（integrate / verify）等控制者确认后再做。

### 反馈候选

- component-check / migrate-manifest 的 `HIST_RE` 对"阶段 + 一"（"每个阶段一行""第一个阶段一般…"）误报 → 留在本仓库工具里改：排除列表加"行"，或只在"阶段"后紧跟数字 / 中文数字且再后面不是汉字时才算。不进 brickKit 信箱（是本项目工具）。
- be-sdk-go 没有给组件测试用的 authz 注入口：想用生产 `RegisterRoutes` 测"带权限的路由到底打到哪个 handler"只能靠 `c.FullPath()` 旁路 → SDK 侧候选（`besdk.WithTestAuthz` 之类，只在测试里可用），进 to-verify 由控制者决定。

## 小结

- 完成：C1–C6。组件仓库 20 个提交（接管后 11 个：4e38cfe、67cd265、dc297bf、b4ed426、68a1a84、19ec32e、17f5c1d、e2f0098、f1c2106、fe3236e、9212623），未推送、未打 tag。
- 需要控制者裁定的：
  - 上游 mdm/customer、mdm/product 已发布 2.0.0，可以进 C7 吗。
  - `gen/mdm/product` 钉在 v1.0.7，上游已有 v1.1.0；本组件没用到新字段，按 component-loop 4.3 不升。是否要升由控制者定。
  - 终态商机上再改阶段 / 赢单 / 输单答 `400`（FailedPrecondition）。按 R49 的措辞"状态冲突"也可以是 409，但契约没有承诺 409，改了就是对已有调用方的行为变更，本次没动。
  - 契约包需要打 `gen/crm/opportunity/v1.0.0`（`go-v2.sh --recheck` 原文：`📌 第 8.3 步需要打的契约包 tag：gen/crm/opportunity/v1.0.0`）。
- 遗留到后续 Task 或下一阶段的：C7–C9；赢单 → 订单 → 回填的业务闭环放 T25 验（需要 T18 erp/sales 在项目里）；`docs/design.md` 未决问题表里的几条（单条读取 403 vs 404、gRPC 无验签、归档任务）。


## R60：没有部门的调用者（重做 C4–C6，版本仍是 2.0.0）

### 目标

按 R60 裁定（`dev/phase-06/dept-scope-analysis.md` §3.1、§6.2 第 4 步的对称清单）修掉"`dept_path` 为空 = 看全部"的 fail-open：没有部门的人在 org 维什么都不命中，只剩本人负责的商机；`"/"` 是显式根标记；没有部门的人能建商机，快照写空串不写哨兵；仓储层空前缀守卫。同时把 `mdm/customer` 钉到已发布的 2.0.1，重做 C4–C6，C7 之前停下。

### 环境

- 日期 2026-10-02；brickKit `BrickKit CLI v1.1.0`；SDK be-sdk-go v0.4.0 → **v0.5.0**（`git ls-remote` 上有 `refs/tags/v0.5.0`）。
- 起点：组件仓库 HEAD 9212623（上一轮 C6 结束）。项目 `brickkit.yaml` 里 `mdm/customer` 已是 2.0.1、`infra/authz` 2.0.1、`infra/workflow` 2.0.1；本组件还没加入项目。
- 测试库 `brickkit_test_db`（`TEST_PG_DSN` 由 env.sh 拼出，不打印值），NATS `nats://localhost:4222`。没有起任何组件容器。

### 步骤

1. 先做一处不改行为的提取：`service.creatorSnapshot(ctx)`（建档快照，v0.4.0 下与原来逐字相同），让快照测试在 v0.4.0 上能编译。
2. 写红测试（真 PG）：`backend/internal/service/nodept_test.go`（无部门的人 dept 列表为空、dept 漏斗为零、看别人的商机与阶段历史 404、赢别人的商机 Forbidden 且不改库、建的商机快照为空且只有本人看得到、跨组件版的建档快照、根标记 `"/"`）；`backend/internal/repo/nodept_test.go`（dept 视角 List / Funnel 空前缀 → `ErrInvalidArgument`；mine 视角不需要前缀）；`backend/internal/http/nodept_test.go`（REST 默认列表为空、别人的商机 404、自己的 200）。
3. 在 **v0.4.0** 上跑红（`go test ./backend/internal/... -race -count=1 -run 'NoDept|无部门|根标记|ScopePrefix留空|mine视图不需要' -v`，日志 `$S/red-r60-v040.log`），原文：

```
    nodept_test.go:22: 默认视图：期望 200 且空列表，实际 200、50 条
--- FAIL: TestNoDept_REST列表为空且别人的商机答404 (0.13s)
    nodept_test.go:23: dept 视图 ScopePrefix 为空：期望 ErrInvalidArgument，实际 err=<nil>、200 条
--- FAIL: TestListOpportunities_dept视图ScopePrefix留空报InvalidArgument (0.25s)
    nodept_test.go:33: dept 视图 ScopePrefix 为空：期望 ErrInvalidArgument，实际 err=<nil>、[{1 初步接洽 351 NaN NaN} {2 需求确认 28 280000.00 45000.00} {3 方案报价 50 192200.60 96100.36} {4 商务谈判 0 0.00 0.00} {5 赢单 0 0.00 0.00}]
--- FAIL: TestFunnel_dept视图ScopePrefix留空报InvalidArgument (0.05s)
--- PASS: TestListOpportunities_mine视图不需要ScopePrefix (0.05s)
    nodept_test.go:71: 没有部门的人 dept 视图期望空列表，实际 200 条（第一条 dept_path="" owner="u_nodept-me-1790945301583859307-1"）
--- FAIL: TestListOpportunities_无部门的人dept视图看不到任何商机 (0.25s)
    nodept_test.go:102: 没有部门的人 dept 视图每个阶段都应为零，阶段 1 实际 {StageID:1 StageName:初步接洽 Count:354 ExpectedAmount:NaN WeightedAmount:NaN}
--- FAIL: TestFunnel_无部门的人dept视图为零 (0.06s)
    nodept_test.go:117: 有部门的别人的商机：期望 ErrNotFound（与不存在一样），实际 err=<nil> 商机=&{585 无部门测试商机 C-nodept-get-1790945301899440054-22 无部门测试客户 u_east-1790945301899450137-23 12 /1/12/ 1 初步接洽 [{P-1790945301900004552-25 SKU-X 测试产品 EA 1.000000 1000.00 1000.00}] 1000.00 10 100.00 0001-01-01 00:00:00 +0000 UTC OPEN CNY  0001-01-01 00:00:00 +0000 UTC  1 2026-10-02 14:48:21.922633 +0200 CEST 2026-10-02 14:48:21.922633 +0200 CEST}
--- FAIL: TestGetOpportunity_无部门的人看别人的商机是NotFound (0.07s)
    nodept_test.go:134: 有部门的别人的商机：期望 ErrNotFound，实际 err=<nil> 历史=[]
--- FAIL: TestGetStageHistory_无部门的人看别人的是NotFound (0.09s)
    nodept_test.go:148: 有部门的别人的商机：期望 ErrForbidden，实际 <nil>
--- FAIL: TestMarkWon_无部门的人赢别人的商机是Forbidden (0.07s)
    nodept_test.go:189: 同样没有部门的别人：期望 ErrNotFound，实际 <nil>
--- FAIL: TestCreateOpportunity_无部门的人建的商机dept_path留空只有本人看得到 (0.05s)
    nodept_test.go:203: 未设置 MDM_CUSTOMER_GRPC_ENDPOINT，跳过真故障注入测试（需要依赖组件真的在跑）
--- SKIP: TestCreateOpportunity_无部门的人经真实主数据建档dept_path留空 (0.00s)
    nodept_test.go:251: dept_path 为空的别人的商机：期望 ErrNotFound，实际 无权访问该商机
--- FAIL: TestListOpportunities_根标记斜杠看得到所有有部门的商机 (0.05s)
```

   - 红得对：列表 / 漏斗 / 单条 / 阶段历史 / 赢单 / 建档可见性都是 fail-open 本身（无部门的人看到 200 条、漏斗 354 条、赢别人的商机 `<nil>`）。
   - 根标记那条只在最后一步红，原因是单条读取当时答 403、测试期望 404（下一步的行为变更）；列表部分在 v0.4.0 上已经是对的（`LIKE '/' || '%'` 本来就不匹配空串）。这条是特征测试，如实记录。
   - 快照断言在 v0.4.0 上是绿的（旧 SDK 给空前缀，快照恰好是空串）；它要防的是升 SDK 后哨兵被写进行里，见第 6 步。
   - `mine视图不需要ScopePrefix` 是回归保护，一写就绿。
   - 顺带看到：测试库里有 `expected_amount = NaN` 的旧行（上一轮 NaN 类红测试在实现前写进去的），所以 v0.4.0 下全表漏斗的合计显示 `NaN`。现在的校验挡住了新的 NaN；测试库里的残留不影响任何断言（新测试都按客户或按"为零"断言）。
4. 提交 d9d7c29 `test: InScope 的旧用例锁定的是 fail-open…`：`repo/scope_test.go` 的 `{"scopePrefix 为空（部门树根节点）天然匹配全部", …, true}` 改成"空前缀时 org 一侧不命中"（false），另补"空前缀时 owner 一侧照常命中""根标记 / 命中任何真实部门路径""根标记 / 不命中 dept_path 为空的行"。单独一个提交，说明里写了它锁定的是 fail-open。提交后 `TestInScope` 红：`scope_test.go:32: InScope("", "u_me") with DeptPath="/9/99/" OwnerID="u_other" = true, want false`。
5. 提交 075e347 `fix: 单条读取看不到的商机答 404，与不存在的一样`：`service.GetOpportunity` 范围外返回包了 `repo.ErrNotFound` 的错误；已有测试 `TestGetOpportunity_范围外ErrForbidden` 的断言随这个有意的行为变更一起改（改名 `_范围外与不存在一样是NotFound`，补"不存在的 id"）；OpenAPI 的 `GET /opportunities/{id}` 只增 `404` 与说明。写命令仍答 403。只暂存了这一处（`git update-index --cacheinfo`），`creatorSnapshot` 的提取留给下一个提交。v0.4.0 上除新红测试与 `TestInScope` 外全绿（`$S/get404-v040.log`）。
6. 升 SDK：`go get github.com/brickKit/be-sdk-go@v0.5.0 && go mod tidy`（`go: upgraded github.com/brickKit/be-sdk-go v0.4.0 => v0.5.0`），**先不改实现**再跑全部测试（`$S/r60-v050-before-fix.log`），原文：

```
--- FAIL: TestListOpportunities_dept视图ScopePrefix留空报InvalidArgument (0.22s)
    nodept_test.go:23: dept 视图 ScopePrefix 为空：期望 ErrInvalidArgument，实际 err=<nil>、200 条
--- FAIL: TestFunnel_dept视图ScopePrefix留空报InvalidArgument (0.04s)
    nodept_test.go:33: dept 视图 ScopePrefix 为空：期望 ErrInvalidArgument，实际 err=<nil>、[{1 初步接洽 430 NaN NaN} {2 需求确认 31 310000.00 54000.00} {3 方案报价 57 204600.70 102300.42} {4 商务谈判 0 0.00 0.00} {5 赢单 0 0.00 0.00}]
--- FAIL: TestInScope (0.00s)
        scope_test.go:32: InScope("", "u_me") with DeptPath="/9/99/" OwnerID="u_other" = true, want false
--- FAIL: TestCreateOpportunity_无部门的人建的商机dept_path留空只有本人看得到 (0.00s)
    nodept_test.go:169: 快照期望 dept_path="" dept_id="" owner_id="u_nodept-create-1790945389141046406-101"，实际 dept_path="!no-dept" dept_id="!no-dept" owner_id="u_nodept-create-1790945389141046406-101"
```

   SDK 的哨兵让列表、漏斗、单条、赢单在值层面自动 fail-closed（这些测试已经绿），剩下三类：快照把哨兵写进了行（`dept_path="!no-dept" dept_id="!no-dept"`）、repo 的空前缀守卫、`InScope` 的空前缀。
7. 改实现（提交 7d10389）：`creatorSnapshot` 在 `!scope.HasDept` 时写空的 `dept_id` / `dept_path`；`Opportunity.InScope` 空前缀时 org 一侧为假；`ListOpportunities` / `Funnel` 的 dept 视角收到空 `ScopePrefix` 返回 `errEmptyScopePrefix`（包 `ErrInvalidArgument`，REST 400）；改掉 `repo/opportunity.go:199-200`"空前缀 = 全部"的注释。gofmt 把文档注释里的 `''` 改写成 `”`，换了措辞（`dept_path LIKE '%'`）。绿（`$S/green-r60.log`）：本轮新增与改过的 14 条 PASS，1 条 SKIP（跨组件版建档，需要 `MDM_*_GRPC_ENDPOINT`）。
8. 依赖钉版（提交 1080490）：`component.yaml` `mdm/customer@2.0.0` → `@2.0.1`；`Makefile` 的 `dag-check` 按组件核对钉的版本（customer 2.0.1、product 2.0.0）。`go.mod` 不动：`gen/mdm/customer` 远端最新仍是 v1.0.6，`gen/mdm/product` v1.0.7。`brickkit lint crm/opportunity`：`📋 Checked 2 files: 0 with errors, 0 warnings`。
9. 文档（提交 b3b7110）：`docs/design.md`（+zh）数据范围一节、REST 错误一段、未决问题；`BRICKKIT.md`（+zh）部署前准备与契约索引；`AGENTS.md`（+zh）设计取舍、易错点、跳过的测试数。发布说明 `$S/notes-2.0.0.md`：升级前必须做加两条行为变更（无部门只看自己的；单条读取 403 → 404）与依赖版本；补满"新增 / 修复"两节。
10. C4–C6 判据（全部在 HEAD b3b7110 上跑）：
   - `go-v2.sh crm/opportunity --recheck` exit=0：
```
📌 第 8.3 步需要打的契约包 tag：gen/crm/opportunity/v1.0.0（必须等于根 go.mod require 的版本；推送前外壳拉不到）
✅ go-v2.sh：判据全部 PASS
```
   - `go list -m all` 里本仓库恰好两行：`github.com/brickKit/crm-opportunity/v2`、`github.com/brickKit/crm-opportunity/gen/crm/opportunity v1.0.0 => ./gen/crm/opportunity`；`be-sdk-go v0.5.0`、`mdm-customer/gen/mdm/customer v1.0.6`、`mdm-product/gen/mdm/product v1.0.7`。
   - `component-check.sh crm/opportunity` exit=0：
```
🔎 component-check crm/opportunity（/home/zhijie/Desktop/github/be-assembly-standard/components/crm/opportunity，82 个文件）
  PASS  4.5 无驼峰键读取（Go / Python / TS 的 SDK Config 读法）
  PASS  4.5 无旧平台变量 / 旧 API（DATABASE_*、MQ_*、besdk.Endpoint、STORAGE_ENDPOINT；*.go *.py *.ts *.sh Makefile）
  PASS  4.9 scripts/ 里没有旧版本服务名（1-0-N）与 DATABASE_*
  PASS  历史 / 归档引用（§、决策 N、设计计划、阶段…、Task N、docs/plans/、archive/；除 gen/ *.proto migrations/*.sql .claude/）
  PASS  文档 en/zh ## 小节数相等（BRICKKIT / AGENTS / README / docs/design；维护块与代码块不计）
  PASS  文档首行互链（AGENTS / README / docs/design：[English](X.md) · [中文](X.zh.md)）
  PASS  文档没有 ../ 链接（DOC_LINK_NOT_PORTABLE）
  PASS  文档没有越界链接（dev/、archive/）
  PASS  BRICKKIT*.md 没有相对链接
  PASS  文档没有 TODO / TBD / 待填 占位（DOC_PLACEHOLDER）

✅ component-check crm/opportunity：10 项全部 PASS
```
   - `make -C $ROOT docs-check ID=crm/opportunity` exit=0：
```
ℹ️ crm/opportunity is not in brickkit.yaml yet, so it has no configuration to check (brickkit add --local adds it)

📋 Checked 2 files: 0 with errors, 0 warnings
```
   - `make test`（env.sh 开头三行）：
```
go test ./... -race -count=1
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/client	1.272s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/consumer	4.054s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/http	1.484s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/partition	1.085s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/repo	2.793s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/service	2.082s
```
     `-v` 下 `--- PASS` 64 条，`--- SKIP` 3 条（全是跨组件：`TestCreateOpportunity_真实校验客户与产品并取展示快照`、`TestCreateOpportunity_真实客户不存在时拒绝`、`TestCreateOpportunity_无部门的人经真实主数据建档dept_path留空`），0 FAIL。
   - 组件门禁 `make check-version test contract-check import-scan module-check dag-check` exit=0：
```
✓ version=2.0.0（go.mod 主版本一致；HEAD 上没有 tag，或 2.0.0 与 v2.0.0 都在）
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/client	1.247s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/consumer	4.032s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/http	1.429s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/partition	1.085s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/repo	2.435s
ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/service	1.829s
buf breaking --against '.git#tag=v1.0.13'
✓ 无组件间 import
✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规
✓ 依赖 mdm/customer@2.0.1、mdm/product@2.0.0，无 ERP 同步边，无自环
```
   - `make -C $ROOT test-db-init ID=crm/opportunity` exit=0：
```
✓ 建库脚本已产出：tools/be-ops/build/test-db-init.sql（54 个组件，4 个外壳清单，目标库 brickkit_test_db）
✓ 迁移幂等
✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db
```
   - `project-lock.sh -- make -C $ROOT gates` exit=0：
```
✓ 铁律六 import 扫描：0 条违规
✓ SystemClient 误用扫描：0 条违规
✓ 裸路由/裸 resolver 扫描：0 条违规
✓ 事件契约破坏性变更扫描：0 条违规
✓ data-scope-test-scan：0 条违规
✓ dependency-version-scan：0 条违规
✓ service-hostname-scan：0 条错误（0 条警告）
⚠ components/frontend/standard/component.yaml（组件还在 1.x，naming 违规迁移到 2.x 时改名，现在不计入失败）：gatewayBaseUrl:17[naming] iamIssuerUrl:18[naming] casdoorClientId:24[naming]
✓ config-key-scan：0 条违规（另有 1 个 1.x 组件的 3 条 naming 违规只警告，--strict 判红；规则：naming=必须 ^[A-Z][A-Z0-9_]*$，endpoint-suffix=不许以 _ENDPOINT 结尾，reserved=不许撞平台保留名）
✓ openapi-additive-scan：0 条违规（0 条跳过提示）
```
     本组件零违规（唯一的 ⚠ 是 frontend/standard 的 1.x 键名）。锁外另跑发布前两项：`openapi-additive-scan --only crm/opportunity` `0 条违规（0 条跳过提示）`，`config-key-scan --only crm/opportunity --strict` `0 条违规`。

### 现象

- 符合预期的：SDK v0.5.0 的哨兵在值层面就让列表、漏斗、单条读取、赢单对无部门的人 fail-closed，组件代码一行不改这些测试已经转绿（第 6 步）；需要组件自己改的正好是分析 §5.1 预言的那一处：快照把 `Prefix` 写进了行。
- 不符合预期的：`migrate-manifest.py --check` 现在报 `依赖不是 @2.0.0: ['mdm/customer@2.0.1']`（exit 1），`--write` 也只会写 `@2.0.0`（`dep_to_v2` 写死），而且 `component.yaml` 现在是 C3 之后手改的，再跑 `--write` 会触发手改保护（exit 3）。这一项不在本轮要求的判据里，判据全部通过；但 sales（workflow@2.0.1）、iam（authz@2.0.1）、bff（workflow@2.0.1）会撞上同一处。

### 卡点与绕过

- 没有翻 brickKit 源码。读了 be-sdk-go v0.5.0 的发布说明（哨兵、`HasDept`、`"/"`）。
- 依赖钉版只能手改 `component.yaml`（迁移工具不支持 2.0.0 以外的版本，见上），没有改共享工具。
- `mv` 三个同名的 `nodept_test.go` 进同一个暂存目录时只挪走了第一个，另外两个原地未动、没有丢；之后改用"只暂存一处"的办法拆提交。

### 结论

R60 在本组件落地：没有部门的人 dept 视图为空、漏斗为零、看别人的商机与阶段历史 404、写别人的商机 403，能建商机且快照为空、只有本人可见；`"/"` 看得到所有有部门的商机；repo 不再把空前缀当"不限"。单条读取范围外改答 404（行为变更，进发布说明）。依赖 `mdm/customer@2.0.1`。C4–C6 判据全部通过，组件仓库 HEAD b3b7110（未推送、未打 tag），C7 等控制者确认。

### 反馈候选

- `migrate-manifest.py`：`deps_add` / `dep_to_v2` 只认 `@2.0.0`，`--check` 的"依赖不是 @2.0.0"一项把已发布补丁版本（2.0.1）判成问题 → 本仓库工具改：overrides 加一个 `deps_pin`（`{id: version}`），`--check` 接受"2.x 且远端有这个 tag"。四个 06b 组件（opportunity、sales、iam、bff）都要用。
- be-acceptance `data-scope-test-scan` 的可选加固（分析 §6.3）：声明了 `org` 维的组件必须有名字含"无部门"或"no dept"的测试——本组件现在有 8 条（service 7 条名字含"无部门"，http 1 条 `TestNoDept_…`），可以作为这条启发式的正例。


## C7–C9：接入项目、真机验证、交接（版本仍是 2.0.0）

### 目标

上游 mdm/customer 2.0.1、mdm/product 2.0.0、infra/authz 2.0.1、infra/iam-casdoor 2.0.0 都已在项目里，做 C7–C9：依赖钉版改走 `deps_pin`；清掉测试库里 NaN 红测试的残留；`seed-clean` 后灌种子；`make integrate` / `make verify … FOCUS=1 SEED=1 FORCE_BUILD=1`。这是 test-cross（cdb5510 修好之前一直静默失效）第一次真跑，三条跨组件测试必须 PASS；dev.superuser（根部门）带 token 要看得到别的部门的种子商机；Review Focus 2 给一个有默认值的键配非默认值，从行为上确认生效。

### 环境

- 日期 2026-10-02（16:10–16:50 CEST）；`BrickKit CLI v1.1.0`；be-sdk-go v0.5.0。
- 起点：组件仓库 HEAD b3b7110，工作区干净。基础资源（be-postgres、be-nats、be-casdoor、be-rustfs、be-traefik）在跑，没有项目容器，本地模式关。
- erp/sales 与本组件并行走 C7（第一次 integrate 时它已在 `brickkit.yaml` 里但 `DEFAULT_WAREHOUSE_ID` 还空着，见步骤 5）。P9 的回填消费者照旧只靠测试私有 subject 的 L2 测试验，真实 `sales.order.created.v1` 放 T25。

### 步骤

1. **依赖钉版走工具**：`dev/phase-06/tools/manifest-overrides.yaml` 本组件一段加 `deps_pin: {mdm/customer: 2.0.1}`（只动这一段；同文件里 erp/sales、infra/iam-casdoor 的 `deps_pin` 是别的工作线的，没碰）。`migrate-manifest.py crm/opportunity --write`（`$S/c7-manifest-write.log`）：
   ```
   component.yaml：未改动（已是目标内容）
   assembly.yaml：未改动（已是目标内容）
   ⚠️  notes-2.0.0.md 的"## 升级前必须做"一节与重新生成的不同（overrides 改过，或人改过这一节）
   ```
   生成结果与 1080490 手改的 `component.yaml` 逐字相同，手改保护没有触发，不需要 `--force`。`--check`：`依赖: ['mdm/customer@2.0.1', 'mdm/product@2.0.0']`、`✅ --check 全部为"无"`、exit=0。⚠️ 那一行：`diff notes-2.0.0.md notes-2.0.0.generated.md` 的差异只有有意补进"升级前必须做"的三行（依赖版本、两条行为变更）以及"新增 / 修复"两节，生成的部分没有漂移。
2. **种子脚本注释**（c2e4ccd）：`scripts/seed.sh:119` "归属分别是 dev.superuser/无部门" → "dev.superuser/总部（根部门 /1/）"。只改 echo 文字。
3. **测试库 NaN 残留**（锁内，`$S/c7-nan-cleanup.sql` / `.log`）：删之前只读查过：`expected_amount = 'NaN'` 3 行，共 971 行；外键是 `opportunity_items`、`opportunity_stage_history` → `opportunities`（NO ACTION）。一个事务里先删明细再删主行：
   ```
    kind | id  | opportunity_id
    item | 286 |            286
    item | 287 |            287
    item | 304 |            314
   DELETE 3
   DELETE 0            （stage_history 没有这三条的行）
    opportunity | 286 | 金额校验 | C-1790937362384225725-2
    opportunity | 287 | 金额校验 | C-1790937362430179982-5
    opportunity | 314 | 测试商机 | C-1790937362704291557-110
   DELETE 3
    nan_left = 0
   COMMIT
   ```
   删掉的就是这些：商机 286、287（`金额校验`，owner `u_validate`）、314（`测试商机`，owner `u_test_owner`），都在 `/1/12/`，都是 OPEN，创建于 10:36:02 UTC；外加它们的 3 条明细行（286、287、304，金额都正常）。别的行一行没动；明细里没有任何 NaN 列。
4. **复核**（HEAD c2e4ccd）：`component-check.sh` `✅ 10 项全部 PASS`；`make test` 6 个包 ok；`project-lock.sh -- make gates` exit=0，九个门禁 0 违规（唯一的 ⚠ 仍是 frontend/standard 的 1.x 键名）。
5. **seed-clean**：`make -C components/crm/opportunity seed-clean`（锁内）**失败**：
   ```
   ERROR:  relation "command_idempotency" does not exist
   make: *** [Makefile:129: seed-clean] Error 1
   ```
   原因：演示库 `brickkit_db` 有 `crm_opportunity` schema 但一张表都没有（本组件 2.0.0 的迁移从没在演示库跑过），而且第 ① 步无条件查 `erp_sales.command_idempotency`，erp/sales 不在项目里时（本组件可以单独跑）也会同样失败（演示库此时 `erp_sales` 也没有表）。修（5457d35）：`to_regclass` 先判表在不在，本组件的表不在 → `✓ … 没有种子要撤销` exit 0；`erp_sales` 的表不在 → 跳过联带订单。重跑：`✓ crm_opportunity 的表还不存在（迁移没在 brickkit_db 跑过），没有种子要撤销`。`has_table` 对三张表：`erp_sales.command_idempotency: 无`、`mdm_customer.customers: 有`、`crm_opportunity.command_idempotency: 无`。erp_sales 那一支没法端到端跑（要先有种子再删掉它），只核了判断条件。因为演示库里从没有过本组件的行，分析 §5.1 担心的"`dept_path` 为空的旧种子行"这里并不存在。
6. **`make integrate ID=crm/opportunity`**：
   - 第一次（`$S/c7-integrate.log`）exit=2：第 1–5 步都过（`➕ Adding crm/opportunity@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`📝 Config skeletons: config/crm-opportunity.yaml`、`写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`、teardown 已同步、`0 with errors, 0 warnings`），第 6 步 `up --dry-run` 报 `Missing config: erp/sales@2.0.0 → DEFAULT_WAREHOUSE_ID`（`config/erp-sales.yaml` 还是 `DEFAULT_WAREHOUSE_ID: ""`）。这是并行的 sales 工作线 integrate 停在 config-fill 留下的中间态，不是本组件的事，没有去碰别人的配置；后台等它填上值（约 1 分钟）。
   - 第二次（`$S/c7-integrate-2.log`）exit=0：`✓ config/crm-opportunity.yaml：无需改动`、`✓ deploy.teardown.yaml 已与 deploy.yaml 一致`、`✅ crm/opportunity@2.0.0 starting (top-level)`、`✓ integrate crm/opportunity@2.0.0 完成`。
   - 不需要人给值：本组件没有表外的 required 键。
7. **Review Focus 2**（有默认值的键配非默认值）：本组件**没有带默认值的自有键**，只有共享键 `PG_PORT`、`PG_SCHEMA`、`OTEL_BASE_URL`。`PG_SCHEMA` 的默认值与 config 字面量相同，平时分不出读的是哪个，所以真机把它配成 `crm_opportunity_rf2`，整段在同一把锁里做（`$S/rf2.sh`，16:30–16:32；改 config → `CREATE SCHEMA crm_opportunity_rf2 AUTHORIZATION crm_opportunity_rw` → `make verify KEEP=1 FORCE_BUILD=1 OUT=$S/verify-rf2` → 核对 → down → config 逐字节还原 → `DROP SCHEMA … CASCADE`）：
   ```
   verify 前：crm_opportunity 表数 0，crm_opportunity_rf2 表数 0
   容器 brickkit-be-assembly-standard-crm-opportunity-2-0-0-1：PG_SCHEMA=crm_opportunity_rf2
   verify 后：crm_opportunity 表数 0，crm_opportunity_rf2 表数 17
   rf2 的迁移状态表：schema_migrations_crm_opportunity_rf2
   | GET /crm/opportunity/opportunities 带 token → 200 | FAIL | 实际 500 |
   {"level":"ERROR","msg":"周分区维护失败","error":"SET LOCAL ROLE crm_opportunity_rf2_rw: ERROR: role \"crm_opportunity_rf2_rw\" does not exist (SQLSTATE 22023)"}
   config 已还原（与备份逐字节相同）
   已删 schema crm_opportunity_rf2
   crm_opportunity 表数（应仍为 0）：0
   ```
   结论：新键确实被读到了，迁移和服务两边都是。迁移把 17 张表和迁移状态表 `schema_migrations_crm_opportunity_rf2` 建进 rf2，`crm_opportunity` 里一张都没有；服务的事务切的是从配置值派生的角色 `crm_opportunity_rf2_rw`。带 token 那次 500 是文档写明的约束：BRICKKIT.md 的 `PG_USER` 一行写着 "the role name must be `<PG_SCHEMA>_rw`"（`module.go:28 role := schema + "_rw"`），不是读错键。
   想照这条约束补一次全绿：再建登录角色 `crm_opportunity_rf2_rw`（口令与 `crm_opportunity_rw` 相同，从 `.env` 读，不打印），`PG_USER` 一起改，schema 属主给它（`$S/rf2b.sh`，16:33–16:37）。结果迁移失败：
   ```
   迁移 up 失败（schema crm_opportunity_rf2）：… must be able to SET ROLE "crm_opportunity_rw" … ALTER TABLE opportunity_stages OWNER TO crm_opportunity_rw;
   ```
   迁移 SQL 把属主写死成 `crm_opportunity_rw`（001 里 5 处、002 里 2 处）。12 个有迁移的组件全是这样（见反馈候选）。之后同样全部还原：config 逐字节一致，schema 与角色已删，`crm_opportunity` 表数 0。
8. **`make verify ID=crm/opportunity ROUTE=/crm/opportunity/opportunities FOCUS=1 SEED=1 FORCE_BUILD=1`**（16:38–16:42，`$S/c7-verify.sh`，在 verify 后面加了 `KEEP=1` 和带 token 的范围核对，同一把锁；输出目录 `$S/verify-c7/`，汇总 `$S/verify-c7/summary.md`）：
   ```
   | 检查项 | 结果 | 原因 | 日志 |
   |---|---|---|---|
   | brickkit build crm/opportunity | PASS |  | build.log |
   | 镜像 crm-opportunity:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
   | brickkit up -f deploy.verify.yaml | PASS |  | up.log |
   | 迁移容器 Exited (0)（5 个） | PASS |  | migration-*.log |
   | crm-opportunity-2-0-0 running (healthy)（容器服务 crm-opportunity-2-0-0） | PASS |  | status.log |
   | GET /healthz → 200 | PASS |  | http.log |
   | GET /crm/opportunity/opportunities 不带 token → 401/503 | PASS | 实际 401 | http.log |
   | GET /crm/opportunity/opportunities 带 token → 200 | PASS |  | http.log |
   | make -C components/crm/opportunity seed | PASS |  | seed.log |
   | make test-cross ID=crm/opportunity | PASS |  | test-cross.log |
   | focus：宿主机 http://localhost:8102/healthz → 200 | PASS |  | focus.log |
   | brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
   | brickkit local off | PASS |  | local-off.log |
   | brickkit down | SKIP | KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml |  |
   ✓ 全部 PASS 或写明原因的 SKIP
   ```
   - 迁移（演示库第一次建表）：`"msg":"迁移结束","schema":"crm_opportunity","outcome":"ok","version":5,"dirty":false`。容器日志 0 条 ERROR、0 条 WARN。
   - 种子灌完后演示库（`dept_path` 都有值，没有空的）：
     ```
      /1/   | e88c4f5a-… | LOST 1 / OPEN 3 / WON 1
      /1/2/ | 4f269a9f-… | LOST 1 / OPEN 3 / WON 2
     ```
   - focus 下 authz / iam 的地址在宿主机解析不了（`lookup infra-authz-2-0-1 on 127.0.0.53:53: server misbehaving`，日志是 WARN），这是 component-loop 7.4 写明的预期，focus 只验 `/healthz`。
   - 加在后面的带 token 范围核对**没能跑成**：curl 全部 `000`。原因：`brickkit up --focus` 把项目切成 focus 状态，焦点闭包外的容器（authz、iam、本组件的容器）都被收掉了，只剩 mdm 两个。所以 `KEEP=1` 加 `FOCUS=1` 留不下容器形态（见反馈候选）。
9. **带 token 的范围核对**（单独一把锁，`$S/c7-scope.sh`：`make verify … KEEP=1 OUT=$S/verify-c7-scope`，镜像就是上一步从 HEAD 5457d35 `--force` 构建的那个；汇总表与上一步相同，seed / focus 是"没设"的 SKIP）：
   ```
   dev.superuser  view=dept 列表：11 条； {('/1/2/', 'WON'): 2, ('/1/', 'LOST'): 1, ('/1/', 'WON'): 1, ('/1/', 'OPEN'): 3, ('/1/2/', 'LOST'): 1, ('/1/2/', 'OPEN'): 3}
   dev.sales.east view=dept 列表：6 条； {('/1/2/', 'WON'): 2, ('/1/2/', 'LOST'): 1, ('/1/2/', 'OPEN'): 3}
   dev.superuser  view=dept 漏斗：[('初步接洽', 2, '8000.00', '800.00'), ('需求确认', 0, '0.00', '0.00'), ('方案报价', 2, '132000.00', '66000.00'), ('商务谈判', 2, '285000.00', '199500.00'), ('赢单', 0, '0.00', '0.00')]
   dev.sales.east view=dept 漏斗：[('初步接洽', 1, '3000.00', '300.00'), ('需求确认', 0, '0.00', '0.00'), ('方案报价', 1, '120000.00', '60000.00'), ('商务谈判', 1, '250000.00', '175000.00'), ('赢单', 0, '0.00', '0.00')]
   dev.superuser  view=mine 列表：5 条； {('/1/', 'LOST'): 1, ('/1/', 'WON'): 1, ('/1/', 'OPEN'): 3}
   dev.sales.east view=mine 列表：6 条； {('/1/2/', 'WON'): 2, ('/1/2/', 'LOST'): 1, ('/1/2/', 'OPEN'): 3}
   dev.superuser  view=mine 漏斗：[('初步接洽', 1, '5000.00', '500.00'), ('需求确认', 0, '0.00', '0.00'), ('方案报价', 1, '12000.00', '6000.00'), ('商务谈判', 1, '35000.00', '24500.00'), ('赢单', 0, '0.00', '0.00')]
   dev.sales.east view=mine 漏斗：[('初步接洽', 1, '3000.00', '300.00'), ('需求确认', 0, '0.00', '0.00'), ('方案报价', 1, '120000.00', '60000.00'), ('商务谈判', 1, '250000.00', '175000.00'), ('赢单', 0, '0.00', '0.00')]
   dev.sales.east GET 总部的 seed-opp-1（id 1）→ 404（期望 404）
   dev.superuser  GET 华东的 seed-opp-6（id 6）→ 200（期望 200）
   dev.superuser  GET seed-opp-6 的 stage-history → 200（期望 200）
   ```
   根部门的 dev.superuser 在 dept 视图里看得到华东的 6 条。它的 dept 漏斗正好是自己的 mine 漏斗加上华东的漏斗（2 = 1+1，8000.00 = 5000.00+3000.00，…）；`view=mine` 只剩本人的 5 条（视角是切换，不是 OR）。华东看总部的商机 404。收尾：`Local mode: off`，本项目容器 0。
10. **test-cross 逐条核对**：verify 里的 test-cross 不带 `-v`，SKIP 也会显示 `ok`（`$S/verify-c7/test-cross.log` 只有 6 行 `ok`），光看它分不出三条跨组件测试是跑了还是跳了。所以又开一把锁（`$S/c7-cross-v.sh`：`make verify … KEEP=1` → `make test-cross ID=crm/opportunity ARGS="-count=1 -v -run 'TestCreateOpportunity_(…)'"` → down）：
    ```
        MDM_CUSTOMER_GRPC_ENDPOINT=http://localhost:20090
        MDM_PRODUCT_GRPC_ENDPOINT=http://localhost:20092
    --- PASS: TestCreateOpportunity_无部门的人经真实主数据建档dept_path留空 (0.29s)
    --- PASS: TestCreateOpportunity_真实校验客户与产品并取展示快照 (0.24s)
    --- PASS: TestCreateOpportunity_真实客户不存在时拒绝 (0.10s)
    ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/service	1.660s
    test-cross -v exit=0
    Local mode: off
    本项目容器：0
    ```
11. **C8**：发布说明 `$S/notes-2.0.0.md` "修复"一节补了 seed-clean 一条，其余在 R60 那一轮已经写满，复核过。组件提交（不推送、不打 tag）：
    ```
    5457d35 fix: seed-clean 在表不存在时不再失败
    c2e4ccd chore: 种子脚本注释改正：dev.superuser 现在在根部门
    b3b7110 docs: 没有部门的调用者与单条读取 404 写进四对文档（R60）
    ```
    `origin/main..HEAD` 27 个提交，工作区干净。最终判据（HEAD 5457d35）：`component-check` 10 项 PASS；组件 `make check-version dag-check contract-check import-scan module-check` exit=0（`buf breaking --against '.git#tag=v1.0.13'`；`✓ 依赖 mdm/customer@2.0.1、mdm/product@2.0.0`）；`go-v2.sh --recheck` `✅ 判据全部 PASS`，`📌 gen/crm/opportunity/v1.0.0`。verify 用的镜像就是 HEAD 5457d35 构建的，之后组件没有改动，8.6 不需要重跑。

### 现象

- 符合预期的：三条跨组件测试第一次真跑全部 PASS（含新的无部门建档测试）；容器形态、种子、focus 都 PASS；根部门的 dev.superuser 看得到别的部门的种子商机，华东只看到自己的，跨部门单条读取 404；漏斗按视角切换，数对得上；迁移在演示库第一次建表 `outcome=ok`；`PG_SCHEMA` 的非默认值迁移和服务两边都读到了。
- 不符合预期的：
  - `seed-clean` 在空库上和 erp/sales 缺席时会失败（已修，5457d35）。
  - 种子脚本的 `ok` 行无条件写"WON→已自动转订单""erp-sales 真实拒绝确认，infra-workflow 真的多一条异常待办"。本次闭包里没有 erp/sales，这些都没有发生，脚本也不核对。只是文字误导，行为没有问题；没改，免得再跑一轮 verify（见反馈候选）。
  - `PG_SCHEMA` 实际上不能配成非默认值，见步骤 7 与反馈候选。

### 卡点与绕过

- 没有翻 brickKit 源码。读了本仓库的 `infra/scripts/verify-component.sh`（KEEP / FOCUS 的顺序）、`infra/scripts/lib/seed-net.sh`（`get_app_jwt`、`with_toolbox`）、`migrations/001_*.up.sql`（`OWNER TO`）、各组件 `backend/module/module.go`（`role := schema + "_rw"`）。
- integrate 第一次被 erp/sales 的中间态挡住：等它的工作线填值，没有去碰 `config/erp-sales.yaml`。
- `KEEP=1` 加 `FOCUS=1` 留不下容器：带 token 的核对与 `-v` 的 test-cross 各自另开一把锁，用 `KEEP=1` 不带 FOCUS 的 verify 再起一次。

### V 项

- 没有新的 V 项实测。

### 结论

C7–C9 完成。integrate exit=0；verify（FOCUS / SEED / FORCE_BUILD）全部 PASS，只有 KEEP=1 带来的一条写明原因的 SKIP；test-cross 三条跨组件测试 PASS；dev.superuser（根部门）看得到别的部门的商机；`PG_SCHEMA` 非默认值从行为上生效（附带发现它在部署上其实配不了）。组件仓库 HEAD 5457d35，未推送、未打 tag。发布要打的 tag：`gen/crm/opportunity/v1.0.0`（契约包，第一个）、`2.0.0`、`v2.0.0`。

### 反馈候选

- **`PG_SCHEMA` 名义上可配，实际配不了**（本项目，跨 12 个组件）：角色由 schema 派生（`role := schema + "_rw"`，BRICKKIT.md 写明），迁移 SQL 又把属主写死成注册表里的角色（`ALTER TABLE … OWNER TO crm_opportunity_rw`）。于是 `PG_SCHEMA` 一旦不是默认值：保留默认登录角色时，服务 `SET LOCAL ROLE <新 schema>_rw` 失败（500）；换成新角色登录时，迁移 `must be able to SET ROLE "crm_opportunity_rw"` 失败。两条路都走不通（PG 也不允许两个角色互为成员）。建议二选一：把 `PG_SCHEMA` 改成不可配（去掉默认值，文档写"必须等于 registry 的 schema"），或者迁移不写属主（以 `PG_USER` 登录建表，天然就是属主），角色也不再由 schema 派生（standalone 时用 `PG_USER`，外壳里由外壳给出）。这关系到所有组件，交给控制者裁定，不进 brickKit 信箱。
- **`make verify` 的 `KEEP=1` 加 `FOCUS=1`**（本仓库工具）：focus 那一步把容器形态收掉了，`KEEP=1` 留下的只有焦点依赖（mdm 两个），不是文档说的"容器留着"。建议 verify 在 `KEEP=1` 时 focus 之后再 `brickkit up -f deploy.verify.yaml` 恢复容器形态，或者文档写明两者不能一起用。
- **verify 的 test-cross 不带 `-v`**（本仓库工具）：SKIP 也显示 `ok`，汇总表的 PASS 分不出跨组件测试是跑了还是跳了（cdb5510 之前那种静默失效就是这样被盖住的）。建议 test-cross 带 `-v`，汇总里数 `--- SKIP`，有就判 FAIL 或至少列出名字。
- **种子脚本的 ok 行写的是没核对过的结果**（本组件，下次改种子时顺带）：WON 后"已自动转订单"只在 erp/sales 在跑时成立；改成按 `erp_sales` 里有没有 `crm-won:<id>` 的订单来打 ok，或者改写成"erp/sales 在跑时会……"。

## 小结（C7–C9）

- 版本 2.0.0；组件提交 c2e4ccd、5457d35（HEAD 5457d35），未推送、未打 tag，等控制者 `make ship`（tag：`gen/crm/opportunity/v1.0.0`、`2.0.0`、`v2.0.0`）。
- 父仓库待控制者按路径提交：`components/crm/opportunity`（指针，ship 后）、`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/crm-opportunity.yaml`（新文件）、`AGENTS.md` / `AGENTS.zh.md`（组件表）、`dev/phase-06/tools/manifest-overrides.yaml`（本组件一段的 `deps_pin`）、本记录。这几份共享文件里也有 erp/sales、iam-casdoor 等别的工作线的改动。
- 遗留：赢单 → 订单 → 回填的闭环放 T25；上面的四条反馈候选。

## R63：数据库身份只来自配置（版本仍是 2.0.0）

> 这一轮的执行者没有写记录就交了复审；本节由发布前修复轮按 `$S/r63/`、`$S/verify-r63b/` 里的日志与提交说明补写，原文都摘自这些文件。

### 目标

按 R63 裁定：模块 `SET LOCAL ROLE` / `WithTx` 用的角色取配置 `PG_USER`，不再由 `PG_SCHEMA + "_rw"` 推出；迁移里不写死角色名与 schema 名（删掉 `ALTER … OWNER TO crm_opportunity_rw`，只做零效果的删除），以 `make test-db-init` 幂等与两库表属主不变证明；写一条 L2 测试，在测试库里用非默认 schema 加一个名字与它无关的登录角色迁移并运行组件，用完清理。这也回答了 C7–C9 反馈候选里的"`PG_SCHEMA` 名义上可配，实际配不了"。

### 环境

- 2026-10-02 17:48–18:07 CEST；`BrickKit CLI v1.1.0`；be-sdk-go v0.5.0；起点 HEAD 5457d35。
- 测试库 `brickkit_test_db`（`TEST_PG_DSN` 由 env.sh 拼出，不打印值）；演示库 `brickkit_db` 只读查属主。
- 日志目录 `$S/r63/`；真机 `$S/verify-r63/`（磁盘满那次）、`$S/verify-r63b/`（重跑）。

### 步骤

1. **先写红测试** `backend/module/identity_test.go`：建一个随机 schema（`r63_opp_<随机>`）和一个名字与它无关的登录角色（`r63_login_<随机>`），给 `USAGE, CREATE`，以这个角色迁移，再以 standalone 与外壳两种形态起模块，等后台循环建出下周分区并核对分区属主是这个角色，最后清理 schema 与角色。
   - 红 1（`$S/r63/red.log`，17:48，迁移还带 `OWNER TO`）：
     ```
     2026/10/02 17:48:44 WARN 迁移结束 direction=up schema=r63_opp_dlugyld9619p outcome=failed version=1 dirty=true
         identity_test.go:79: 以角色 r63_login_dlugyld9619p 迁移进 schema r63_opp_dlugyld9619p 失败: 迁移 up 失败（schema r63_opp_dlugyld9619p）：migration failed: must be able to SET ROLE "crm_opportunity_rw" (column 0) in line 1: -- crm-opportunity 核心表：商机主体/行/阶段流转历史/阶段定义、客户展示
              (details: ERROR: must be able to SET ROLE "crm_opportunity_rw" (SQLSTATE 42501))
     --- FAIL: TestModule_非默认schema与任意名字的登录角色 (0.08s)
     ```
   - 删掉 `OWNER TO` 之后的红 2（`$S/r63/red2.log`，17:49，迁移已通过，模块仍从 schema 推角色）：
     ```
     2026/10/02 17:49:25 INFO 迁移结束 direction=up schema=r63_opp_dlugz48evu80 outcome=ok version=5 dirty=false
     time=2026-10-02T17:49:25.947+02:00 level=ERROR msg=周分区维护失败 error="SET LOCAL ROLE r63_opp_dlugz48evu80_rw: ERROR: role \"r63_opp_dlugz48evu80_rw\" does not exist (SQLSTATE 22023)"
         identity_test.go:103: 15 秒内后台循环没有建出分区 r63_opp_dlugz48evu80.event_outbox_2026_10_26
         identity_test.go:109: 15 秒内后台循环没有建出分区 r63_opp_dlugz48evu80.event_outbox_2026_10_26
     --- FAIL: TestModule_非默认schema与任意名字的登录角色 (30.70s)
         --- FAIL: TestModule_非默认schema与任意名字的登录角色/单跑 (15.13s)
         --- FAIL: TestModule_非默认schema与任意名字的登录角色/外壳 (15.14s)
     ```
   - 绿（`$S/r63/green.log`，17:50，`module.go` 的 `dbIdentity` 取 `PG_USER`，缺键或名字不合法启动即失败）：
     ```
     --- PASS: TestDBIdentity_角色取PG_USER不从schema推 (0.00s)
     --- PASS: TestDBIdentity_缺键或非法名字启动即失败 (0.00s)
     --- PASS: TestModule_非默认schema与任意名字的登录角色 (0.83s)
         --- PASS: TestModule_非默认schema与任意名字的登录角色/单跑 (0.24s)
         --- PASS: TestModule_非默认schema与任意名字的登录角色/外壳 (0.24s)
     ok  	github.com/brickKit/crm-opportunity/v2/backend/module	0.844s
     ```
2. **测试身份集中**（da4d217）：各包测试里写死的 `crm_opportunity` / `crm_opportunity_rw` 收进 `backend/testdb`（`Schema`、`Role`，可由 `TEST_PG_SCHEMA` / `TEST_PG_ROLE` 覆盖）；生产代码不 import 它（`module-check` 拦）。整套换身份跑（`$S/r63/alt-suite.sh`，17:52：建 schema `r63_suite_alt` 与登录角色 `r63_suite_login`，以它迁移，再 `TEST_PG_SCHEMA=r63_suite_alt TEST_PG_ROLE=r63_suite_login go test ./... -race -count=1`）：
   ```
   {"level":"INFO","msg":"迁移结束","direction":"up","schema":"r63_suite_alt","outcome":"ok","version":5,"dirty":false}
   owners in r63_suite_alt: r63_suite_login / 23
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/client	1.247s
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/consumer	4.039s
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/http	1.534s
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/partition	1.221s
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/repo	2.431s
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/service	2.037s
   ok  	github.com/brickKit/crm-opportunity/v2/backend/module	2.115s
   go test exit=0
   cleanup: schemas=0 roles=0
   ```
3. **已应用迁移的零效果删除**（a2e7e2e）：001 删 5 行、002 删 2 处 `OWNER TO crm_opportunity_rw`，002 里留了原因注释。`make test-db-init ID=crm/opportunity` 连跑两次（`$S/r63/test-db-init-1.log`、`-2.log`，17:54），两次都是：
   ```
   ▸ ①b 把 postgres 名下的旧对象转给各组件的 <schema>_rw
   ▸ ② 对 1 个已建组件各跑一遍 migrate-idempotent，目标 brickkit_test_db
   {"level":"INFO","msg":"迁移结束","direction":"up","schema":"crm_opportunity","outcome":"ok","version":5,"dirty":false}
   {"level":"INFO","msg":"迁移结束","direction":"up","schema":"crm_opportunity","outcome":"ok","version":5,"dirty":false}
   ✓ 迁移幂等
   ✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db
   ```
4. **表属主前后对比**：`$S/r63/owners-{before,after}-{brickkit_db,brickkit_test_db}.txt`（17:49 / 17:54，`kind|对象|属主`）。`cmp` 两库都逐字节相同；每份 31 个对象，属主全是 `crm_opportunity_rw`：
   ```
   brickkit_db identical
   brickkit_test_db identical
        31 crm_opportunity_rw
   ```
5. **种子脚本**（0a0afd7）：`seed.sh` 只在 GET 回来的 `order_id` 非空时写 `WON→订单 <id>`，否则写 `WON，没有转出订单`；`seed` / `seed-clean` 从项目 `config/` 读各组件的 schema（新 `scripts/schema.sh`），不再写死。测试库上 `seed-clean`（`$S/r63/seed-clean-testdb.log`）：`✓ crm-opportunity 种子数据已清空（联带的 erp-sales 订单删了 0 张）`、`exit=0`。这一条兑现了 C7–C9 的"种子脚本的 ok 行"反馈候选。
6. **文档**（96a5d11）：AGENTS / BRICKKIT / design 两种语言写明数据库身份只来自配置，BRICKKIT "Before you deploy" 写成通用要求（一个 schema、一个有 `USAGE`+`CREATE` 并跑迁移的登录角色；本项目的 registry / db-init 只是提供方式之一）。
7. **判据**（HEAD 96a5d11，17:57–17:58）：`component-check` `✅ 10 项全部 PASS`；`make test` 7 个包 ok（`$S/r63/make-test-1.log`，多了 `backend/module`）；组件 `make check-version test contract-check import-scan module-check dag-check` exit=0；`go-v2.sh --recheck` `✅ 判据全部 PASS`、`📌 gen/crm/opportunity/v1.0.0`；`make gates`（`$S/r63/gates.log`）十个门禁 0 违规，`brickkit up --dry-run` exit=0。
8. **真机 verify，第一次：磁盘满**（`$S/r63/verify-1-diskfull.log`，18:03–18:04）：先等了 erp/sales 的 verify 180 秒拿锁；build 与镜像检查 PASS，`brickkit up` 失败（`$S/verify-r63/up.log`）：
   ```
   ❌ Error: failed to write the Manifest cache
      Reason: write .brickkit/manifests/mdm/customer/2.0.1/component.yaml: no space left on device
   | brickkit up -f deploy.verify.yaml | FAIL | 见日志（缺镜像 / 配置 / 迁移失败 / 健康检查超时） | up.log |
   | 迁移容器 Exited (0) | FAIL | crm/opportunity 声明了 migration，却没找到 *-migration 容器 |  |
   | crm-opportunity-2-0-0 running (healthy) | FAIL | 容器 不存在：无 | status.log |
   | brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
   ```
   根分区写满（这次 verify 自己只写 manifest 缓存，满的原因不在本组件）。R63 的提交都早于这次（96a5d11 在 17:59）；复审核过组件仓库 `git fsck --full` exit 0、86 个跟踪文件没有 0 字节、没有 NUL、`git status` 干净。
9. **真机 verify，重跑**（`$S/verify-r63b/`，18:05–18:07，从 HEAD 96a5d11 强制构建，带 SEED=1，不带 FOCUS）：
   ```
   | brickkit build crm/opportunity | PASS |  | build.log |
   | 镜像 crm-opportunity:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
   | brickkit up -f deploy.verify.yaml | PASS |  | up.log |
   | 迁移容器 Exited (0)（5 个） | PASS |  | migration-*.log |
   | crm-opportunity-2-0-0 running (healthy)（容器服务 crm-opportunity-2-0-0） | PASS |  | status.log |
   | GET /healthz → 200 | PASS |  | http.log |
   | GET /crm/opportunity/opportunities 不带 token → 401/503 | PASS | 实际 401 | http.log |
   | GET /crm/opportunity/opportunities 带 token → 200 | PASS |  | http.log |
   | make -C components/crm/opportunity seed | PASS |  | seed.log |
   | make test-cross ID=crm/opportunity | PASS |  | test-cross.log |
   | brickkit up --focus crm/opportunity | SKIP | 没设 FOCUS=1 |  |
   | brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
   ```
   test-cross 不带 `-v`，但 `test-cross.log` 里有 `MDM_CUSTOMER_GRPC_ENDPOINT=http://localhost:20090`、`MDM_PRODUCT_GRPC_ENDPOINT=http://localhost:20092`，三条跨组件测试只在这两个变量缺席时 SKIP，所以是真跑了。种子的汇总行如实写出：`4(WON，没有转出订单)`、`9(WON，没有转出订单)`、`（没有订单回填：erp/sales 不在这次的闭包里，或没在 等待时间内建单。商机照样是 WON）`。

### 现象

- 符合预期：非默认 schema 加任意名字的登录角色，迁移、standalone、外壳三种形态都通；整套测试在另一套身份上全绿并清理干净；迁移的删除对已建好的两个库零效果（属主逐字节相同，`✓ 迁移幂等`）。
- 不符合预期：第一次 verify 撞上磁盘满（与本组件无关，重跑全绿）。

### 卡点与绕过

- 磁盘满：等空间回来后重跑 verify，没有清理任何东西。
- 没有翻 brickKit 源码。

### 结论

R63 完成，`PG_SCHEMA` / `PG_USER` 现在真的可配：C7–C9 的反馈候选"`PG_SCHEMA` 名义上可配，实际配不了"在本组件已解决（12 个组件的普遍问题由控制者按 R63 分发）。组件提交 a2e7e2e、042df08、da4d217、0a0afd7、96a5d11（HEAD 96a5d11），未推送、未打 tag。

### 反馈候选

- 无新增。focus 在 R63 之后没重跑（M8）：R63 只加了启动时的身份校验，`local` 模式由注入的配置满足，风险低。

## 发布前修复（复审 I1 / I3 / M6，版本仍是 2.0.0）

### 目标

按 `task-19-review.md` 做发布前三项：I1 AGENTS 两种语言不再教人 source `.env`；I3 `PATCH` / `UpdateOpportunity` 没带 `owner_id` 时不能清空负责人，并核对其余可选字段有没有同样"没带就抹掉"的问题；M6 发布说明补 1.x 迁移对象属主一行。I4（幂等重放不核对命令、目标与范围）跨组件，留给设计轮，本轮不碰。

### 环境

- 2026-10-02 18:25–18:45 CEST；`BrickKit CLI v1.1.0`；be-sdk-go v0.5.0；起点 HEAD 96a5d11；根分区开始时 14G 可用，verify 前 110G 可用。
- `TEST_PG_DSN` / `TEST_NATS_URL` 由 `eval "$(bash dev/phase-06/tools/env.sh crm/opportunity)"` 拼出（不打印值）。日志目录 `$S/r64/`，真机 `$S/verify-r64/`。

### 步骤

1. **I1**（a4185fa，docs）：`AGENTS.md:50` / `AGENTS.zh.md:50` 的 `set -a; . ../../../.env; set +a` 删掉，改成与 infra/iam-casdoor 一样的注释：口令是项目 `.env` 里的 `POSTGRES_PASSWORD`（要 URL 编码），不要 source `.env`（Compose 语法，含多行 PEM）；DSN 里写 `<password>` / `<密码>` 占位。组件文档不能链接 `dev/`，所以没有写 env.sh 的路径。
2. **I3 字段逐个核对**（契约 `UpdateOpportunityRequest` 只把 `idempotency_key`、`version` 列为必填）：
   | 字段 | 修复前 REST | 修复前 gRPC | 丢数据？ | 处理 |
   |---|---|---|---|---|
   | `owner_id` | 没带 → 写成 `""` | 空串 → 写成 `""` | 是 | 空 / 没带 → 保留原值 |
   | `expected_close_date` | 没带 → 写成 NULL | nil → 写成 NULL | 是 | 没带 → 保留原值；代价：设了之后只能改、不能清空 |
   | `name` | `binding:"required"`，没带 400 | 空串 → 写成 `""` | gRPC 是 | 空 → `INVALID_ARGUMENT`，两条路一致 |
   | `expected_amount` | 必带，空的 400 | 空的 `INVALID_ARGUMENT` | 否 | 不变（`badAmounts` 里的 `""` 测试照旧守着） |
   契约没有哪一个字段声明了"整体替换"；"full replacement"只写在 BRICKKIT 与 design 里，这一轮改成新语义并写明理由。
3. **I3 红测试**（`$S/r64/red.log`）：新 `backend/internal/repo/update_test.go` 三条、`backend/internal/http/nodept_test.go` 一条（没有部门的人建的商机，PATCH 不带 `owner_id` 后负责人自己再读）：
   ```
       update_test.go:51: 没带 owner_id 不该清空负责人：期望 u_keep_owner，实际 ""
   --- FAIL: TestUpdateOpportunity_没带负责人与预计成交日时保留原值 (0.04s)
   --- PASS: TestUpdateOpportunity_带了新负责人与新预计成交日时照改 (0.03s)
       update_test.go:89: 空名称：期望 ErrInvalidArgument（不是版本冲突），实际 <nil>
   --- FAIL: TestUpdateOpportunity_名称为空时拒绝且不改库 (0.03s)
   --- PASS: TestUpdateOpportunity_金额不是普通十进制时拒绝且不改库 (0.03s)
   --- PASS: TestUpdateOpportunity_版本冲突 (0.03s)
   --- PASS: TestUpdateOpportunity_真实更新 (0.04s)
   FAIL	github.com/brickKit/crm-opportunity/v2/backend/internal/repo	0.222s
   --- PASS: TestUpdateOpportunity_REST版本过期答409 (0.04s)
       nodept_test.go:48: 没带 owner_id 不该清空负责人：期望 "u_rest-nodept-patch-1790958715958401147-6"，实际 
   --- FAIL: TestNoDept_REST改商机不带owner_id时负责人不变且仍看得到 (0.03s)
   FAIL	github.com/brickKit/crm-opportunity/v2/backend/internal/http	0.083s
   ```
4. **I3 修复**（255a87a，fix）：`repo.UpdateOpportunity` 空 `name` 拒绝；SQL 改成 `expected_close_date = COALESCE($3::date, expected_close_date)`、`owner_id = COALESCE(NULLIF($4::text, ''), owner_id)`。OpenAPI 的字段说明、proto 注释（`buf generate` 之后 `gen/` 只有注释变化，契约包 tag 还没打，所以仍是 v1.0.0）、BRICKKIT 与 design 两种语言写明语义与理由。绿（`$S/r64/green.log`）：
   ```
   --- PASS: TestUpdateOpportunity_没带负责人与预计成交日时保留原值 (0.03s)
   --- PASS: TestUpdateOpportunity_带了新负责人与新预计成交日时照改 (0.05s)
   --- PASS: TestUpdateOpportunity_名称为空时拒绝且不改库 (0.03s)
   --- PASS: TestUpdateOpportunity_金额不是普通十进制时拒绝且不改库 (0.03s)
   --- PASS: TestUpdateOpportunity_版本冲突 (0.03s)
   --- PASS: TestUpdateOpportunity_真实更新 (0.03s)
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/repo	0.206s
   --- PASS: TestUpdateOpportunity_REST版本过期答409 (0.04s)
   --- PASS: TestNoDept_REST改商机不带owner_id时负责人不变且仍看得到 (0.03s)
   ok  	github.com/brickKit/crm-opportunity/v2/backend/internal/http	0.069s
   ```
5. **M6 与发布说明**（`$S/notes-2.0.0.md`，改前副本 `$S/r64/notes-2.0.0.before.md`）："升级前必须做"加两行：1.x 迁移以别的身份建的对象（例如 `schema_migrations_crm_opportunity`）要在 2.0.0 迁移之前改归 `PG_USER`，只给 `USAGE` 与 `CREATE` 不够；以及 I3 的行为变更（加粗）。复审说"`make db-init` / `test-db-init` 第 ①b 步做这件事"只对一半：只有 `infra/scripts/test-db-init.sh` 有 ①b，`db-init.sh` 没有；演示库的 31 个对象本来就都归 `crm_opportunity_rw`，所以说明里照实写。
6. **判据**（HEAD 255a87a）：
   - `component-check.sh crm/opportunity`：`✅ component-check crm/opportunity：10 项全部 PASS`，exit=0。
   - `make docs-check ID=crm/opportunity`：`📋 Checked 3 files: 0 with errors, 0 warnings`，exit=0。
   - 组件 `make check-version test contract-check import-scan module-check dag-check` exit=0（`$S/r64/gates-comp.log`）：7 个包 ok，`buf breaking --against '.git#tag=v1.0.13'` 通过，`✓ 依赖 mdm/customer@2.0.1、mdm/product@2.0.0，无 ERP 同步边，无自环`。
   - be-acceptance（`$S/r64/acceptance.log`）：`openapi-additive-scan（只看 components/crm/opportunity）：0 条违规（0 条跳过提示）`、`config-key-scan（只看 components/crm/opportunity）：0 条违规`；全项目只读扫描 bare-route / data-scope-test / import / SystemClient 都是 0 条违规。
   - `go-v2.sh --recheck crm/opportunity`：`✅ go-v2.sh：判据全部 PASS`、`📌 gen/crm/opportunity/v1.0.0`。
7. **真机** `make -C $ROOT verify ID=crm/opportunity ROUTE=/crm/opportunity/opportunities FORCE_BUILD=1 OUT=$S/verify-r64`（`$S/r64/verify.log`，exit=0）：
   ```
   | brickkit build crm/opportunity | PASS |  | build.log |
   | build infra/authz@2.0.1（闭包里缺镜像） | PASS |  | build-infra-authz.log |
   | 镜像 crm-opportunity:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
   | brickkit up -f deploy.verify.yaml | PASS |  | up.log |
   | 迁移容器 Exited (0)（5 个） | PASS |  | migration-*.log |
   | crm-opportunity-2-0-0 running (healthy)（容器服务 crm-opportunity-2-0-0） | PASS |  | status.log |
   | GET /healthz → 200 | PASS |  | http.log |
   | GET /crm/opportunity/opportunities 不带 token → 401/503 | PASS | 实际 401 | http.log |
   | GET /crm/opportunity/opportunities 带 token → 200 | PASS |  | http.log |
   | make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
   | make test-cross ID=crm/opportunity | PASS |  | test-cross.log |
   | brickkit up --focus crm/opportunity | SKIP | 没设 FOCUS=1 |  |
   | brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
   ✓ 全部 PASS 或写明原因的 SKIP
   ```
   test-cross.log 里两个 `MDM_*_GRPC_ENDPOINT` 都在，三条跨组件测试真跑。

### 现象

- 符合预期：四条新测试修复前三红一绿（"带了新值照改"本来就对），修复后全绿；整套测试与全部判据通过；镜像从 HEAD 255a87a 强制构建，真机全绿。
- 不符合预期：gRPC 不带 `name` 会把名字写成空串（复审没提，核对字段时发现，一并修了）。

### 卡点与绕过

- 没有。没有翻 brickKit 源码。

### 结论

I1、I3、M6 完成。组件提交 a4185fa（docs）、255a87a（fix），HEAD 255a87a，`origin/main..HEAD` 34 个，未推送、未打 tag。

### 反馈候选

- `infra/scripts/db-init.sh` 自己也 `set -a; . ./.env; set +a`（本仓库工具，与 I1 同一类）：`.env` 里的多行 PEM 会被当 shell 执行。它在锁里跑、输出不进会话记录时不泄漏，但同样会执行续行；建议改成 dotenv-pgpass.py 那样只读需要的键。
- `components/erp/sales/AGENTS.md:49` 有同样的 source `.env` 一行（复审已转给控制者）。

## 小结（发布前修复）

- 版本 2.0.0；组件 HEAD 255a87a（新增 a4185fa、255a87a），未推送、未打 tag。tag 打在 255a87a 上：`gen/crm/opportunity/v1.0.0`、`2.0.0`、`v2.0.0`；`make ship DIR=components/crm/opportunity NOTES=$S/notes-2.0.0.md`（已含 M6 与 I3 行为变更）。
- I4 没动，留给设计轮。06c 前端 brief 不再需要"PATCH 必须带 owner_id"的提醒。
