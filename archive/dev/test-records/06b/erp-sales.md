# 06b erp/sales：过程记录（T18）

> 本工作线中途被打断后由新会话接手：前一位实现者的会话记录已丢失，没有留下记录与报告。接手时的状态从组件仓库（9 个已提交、5 个未提交文件）、scratch 目录 `$S` 里的日志与提交信息草稿（`msg-1.txt` … `msg-9.txt`）还原。下文标"（日志）"的内容来自这些日志，其余是接手会话实测。

## 概况

- 日期：2026-10-02。前一位实现者约 07:11 开工、07:30 前后中断（最后一个提交 6634a74）；接手会话约 12:40 开始，13:05 停在 C6 结束、C7 之前（W2 提前开工，C7 前要控制者确认上游已发布）
- brickKit：`brickkit version` → `BrickKit CLI v1.1.0`（`/home/zhijie/.local/bin/brickkit`，env.sh 断言）
- SDK：be-sdk-go v0.4.0（`go list -m all` → `github.com/brickKit/be-sdk-go v0.4.0`）
- 基础资源：`make check` → `✓ 全部基础资源就绪`
- 组件与版本：erp/sales v1.0.26 → 2.0.0；形态 B（`gen/erp/sales` 拆成嵌套模块）；组件仓库 19 个提交（01f2a29 … d845965，未推送、未打 tag）；契约包需要新 tag `gen/erp/sales/v1.0.0`
- 本地模式 off，全程没有起项目容器

## erp/sales

### 目标

按 component-loop 重建到 2.0.0（本次只做 C1–C6）；补 frontend-needs §2.4 的 `Order.source_opportunity_id`（赢单消费路径写入）、`GET /orders?source_opportunity_id=`、`GET /stats/summary`，以及 P9 的事件方案（`sales.order.created.v1` 只增可空字段 `source_opportunity_id`）；按 Task 的重构重点审查 `tcc/` 补偿路径、赢单 payload 与 crm 契约逐字段对照、`client/` 的超时与重试、用户请求路径上的 `SystemClient`。控制者追加：所有十进制输入按 NaN 类核对（先红后绿）、R49、R51。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件（C1–C6 不起容器）。项目 `brickkit.yaml` 里此时已有别的工作线加入的 mdm/customer、mdm/product、erp/inventory、erp/finance、infra/workflow 等（都是 2.0.0），erp/sales 还没加入。

### 步骤

**C1 前置**

- env.sh：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`
- 最后一个 1.x tag `v1.0.26`；没有 `gen/*` tag（形态 B）。
- 1.2 仓库干净：前一位实现者开工时满足（日志）；接手时 `## main...origin/main [ahead 9]` + 5 个未提交文件，均为本工作线自己的半成品。
- 1.1 上游：`brickkit.yaml` 里 mdm/customer、mdm/product、erp/inventory、erp/finance、infra/workflow 都是 2.0.0；`ls-remote --tags origin 2.0.0 v2.0.0`：mdm/customer 2 行、mdm/product 2 行、infra/workflow 2 行、**erp/inventory 0 行、erp/finance 0 行**。按 W2 提前开工记"待 C7 前复核"。
- 1.6 表属主：`select tableowner, count(*) … where schemaname='erp_sales'`（brickkit_db）→ 空（演示库里还没有本组件的表）。
- 1.5 读了 `$S/old/` 的旧 AGENTS / README / 手册、`archive/pre-v1/docs/dev/design/erp-sales.md`、清单与构建文件、frontend-needs §2.4、02-backend 相关节、样板 mdm/customer 的 Makefile / Dockerfile / 八份文档、erp-inventory 的记录。

**C2 骨架（日志）**：`docs-skel.sh`、`git rm docs/手册.md`、`brickkit skills update`，九个文件在，维护块在，留底在 `$S/old/`。提交在 01f2a29（与 C3、go-v2 一起的机械步骤提交）。

**C3 清单（日志）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL', 'defaultWarehouseId': 'DEFAULT_WAREHOUSE_ID', 'exceptionAssigneeSub': 'EXCEPTION_ASSIGNEE_SUB'}`；`module.go:34/40/44` 三处读法改成新键；`assembly.yaml：去掉 7 行归档引用注释`（清单在 `$S/assembly-removed-comments.txt`，结论已写进 docs/design.md 的数据范围一节）。
- `brickkit lint erp/sales` → `🔎 Only erp/sales is checked …`、`✅ components/erp/sales/component.yaml`、`📋 Checked 2 files: 0 with errors, 78 warnings`（只有占位符与"文档未提到"）。
- 无新权限键，没跑 `make permissions`。C6 时重跑 `migrate-manifest.py erp/sales --check` → `✅ --check 全部为"无"`、`exit=0`（`ℹ️` 只列出 `backend/module/config_test.go` 里故意写的旧键字符串——那条测试验证旧键不生效）。

**C4 代码**

前一位实现者（日志与提交信息）：

- `go-v2.sh --sdk v0.4.0` 第一次 FAIL：`backend/internal/client/client.go:42:42: not enough arguments in call to besdk.UserClient`（v0.4.0 的 UserClient / SystemClient 要传 Config）。client 包改成持有 `rt.Config` 的 `Clients` 后重跑 `exit=0`、判据全部 PASS、`📌 第 8.3 步需要打的契约包 tag：gen/erp/sales/v1.0.0`。go.mod：`go 1.25.0 => 1.25.11`、`be-sdk-go v0.2.4 => v0.4.0`、`golang-migrate v4.19.1 => v4.20.1`。
- 红绿提交：15b07db 非法游标 400；bcd7fda REST 读 `created_after/before`；d51e838 BatchGetOrder 的 `missing_ids`；c2a62a2 金额十进制（红：`money_test.go:20: computeSubtotal(1, 0.30, 0.05) 期望 0.29，实际 0.28`、`credit_test.go:20: exceedsCreditLimit("0.10", "0.20", "0.30") 期望 false，实际 true`）；3bc1c74 测试本身错了（补偿成功不该计入失败次数，单独提交写明原因）+ 2d45a5b 补偿原地重试三次（红：`compensate_test.go:80: 期望调用 3 次 CancelReservation，实际 1 次` 等四条）；d6daef1 每次同步调用都限时；6634a74 `source_opportunity_id`（迁移 004、赢单路径写入、事件 payload、契约只增；红五条，见提交信息）。
- 接手时未提交：`GET /stats/summary` 的 repo / service / handler 与两份测试，测试全绿，但没有红的证据、OpenAPI 也还没加这条路径。

接手之后（每个红绿一个提交，红的原文都在提交信息里）：

- 0bab8b7 `GET /stats/summary`：先补 OpenAPI（`/stats/summary`、`StatsSummary`、`StatsDay`，只增）；把 `StatsSummary` 换成返回空结果的桩跑红：`stats_test.go:66: period 省略时应是 month、by_day 30 天，实际  / 0 天`、`stats_test.go:125: A 部门：期望 2 单 / 30.00，实际 0 单 /`、`stats_test.go:157: period=week：期望 7 天 / 1 单 / 1.00，实际 0 天 / 0 单 /`、`http_test.go:236: A 默认（dept、month）应看到本部门 2 单、30 天、7 个状态，实际 code=200 {…OrderCount:0…}`；恢复实现后全绿。"两个范围的用户各自只看到自己的数"（两个部门 × 两个 owner，真实建库）与 period 边界（第 6 天在周窗口内、第 7 天在外；第 29 天在月窗口内、第 30 天在外）都有测试。
- 9f48991 NaN 类与数量校验（控制者要求）：
  - NaN 类测试（`NaN`/`nan`/`Inf`/`+Inf`/`-Inf`/`Infinity`/`-Infinity`/`1e3`/`1E3`/`0x10`/`1_000`）在当前代码上是绿的——c2a62a2 已经改成正则校验。为了有红的证据，在 c2a62a2 之前的 d51e838 上开 worktree 跑同一条测试：`qty_test.go:24: qty="NaN" 不是十进制数字，应该是参数错误，实际 <nil>`（worktree 用完即删）。
  - 真正还红的是数量的取值范围：`qty_test.go:41: qty="0" 应该是参数错误（HTTP 400），实际 <nil>`、`qty="-1" … 实际 not found: 没有任何价格表规则命中 …`、`qty="+1" … <nil>`、`qty="0.0000001" … <nil>`、`qty="1.1234567" … <nil>`、`qty="1234567890123" … <nil>`（共 8 条）。实现 `validateQty`：不带符号、整数 ≤ 12 位、小数 ≤ 6 位、> 0；建单、试算、赢单转单三条路径都经过 `findPriceTx`。
- 1316285 客户额度快照：红 `snapshot_test.go:53: credit_limit="NaN" 的事件不该改快照：期望仍是 5000.00，实际 NaN`（`nan`、`1e3`→1000.00、`-1.00`、`0x10`→16.00 同理）、`snapshot_test.go:69: 没带 credit_limit 的 updated 事件不该改额度：期望 8000.50，实际 0.00`。`Infinity` 与 `abc` 原来就被 `NUMERIC(18,2)` 以错误拒绝。修法：只收 `^[0-9]{1,16}(\.[0-9]{1,2})?$`；空串 / 没带 = 额度不变、只推进 version。
- 011788b R51 日志级别：先放一律返回 ERROR 的 `FailureLevel` 桩（即原行为）跑红：`service/loglevel_test.go:111: "发货失败" 是调用方的错误（4xx），不该记 ERROR，实际 ERROR`（确认、取消同理）、`tcc/loglevel_test.go:75: 参数不合法：期望 INFO，实际 ERROR`（12 条）、`tcc/loglevel_test.go:90: 单次补偿失败会原地重试，不该记 ERROR`（×3）、`:101: 连续失败到挂起订单时应恰好记一条 ERROR，实际 3 条`、`:125: 超额度是业务拒绝，不该记 ERROR`、`partition_test.go:119: 月分区：关闭时取消不该记 ERROR，实际 1 条`（周分区同样，map 顺序随机，多跑几次两条都红过）。
- 1728d72 Makefile / Dockerfile 照 mdm/customer 模板（R43）；`dag-check` 改成"依赖全部 @2.0.0、不依赖自己"（在 scratch 里拿一份把 erp/finance 改成 @1.9.0 的 component.yaml 验过它会失败：`✗ 这几条依赖不是 @2.0.0 或指向自己：erp/finance@1.9.0`）；`seed` 先核对 iam-casdoor、authz、mdm/customer、mdm/product 在项目里（照 erp/inventory 的写法）；种子脚本说明去掉历史。`grep -n -i 'customer\|客户' Makefile` 的命中都是对 mdm/customer 依赖的说明，不是模板残留。
- c8f8e80 审查时发现：`module.New` 用 `MustString` 读 `DEFAULT_WAREHOUSE_ID`，缺了 panic（进外壳会带走同外壳的成员），空串照收。抽出 `readConfig` 先保持原读法跑红：`config_test.go:44: map[]：缺 DEFAULT_WAREHOUSE_ID 应返回 error，实际 panic：必填配置项 "DEFAULT_WAREHOUSE_ID" 未注入`、`:48: map[DEFAULT_WAREHOUSE_ID:]：… 应返回 error`；改成返回 error。同一测试也守住 Review Focus 2：`EXCEPTION_ASSIGNEE_SUB` 按确切键名读，驼峰旧键不生效。
- f7890c0 / 15829f1 注释清理（非测试代码、测试各一个提交，只动注释）：组件里的历史引用从 150 余处清到 0。顺带改正五处与代码不符的说明（tcc 包"网络调用全走 UserClient"、赢单 handler"不占 inbox 事务"、"报价差异只记日志"、确认链"信用校验排在网络调用之前"、confirm_test 里过时的"gRPC 没有 panic 恢复"）。
- fc7f6c0 改正 `Order.order_no` 的 `.proto` 注释（缺口来自插入回滚，不是草稿作废）；`buf generate` 后 `go-v2.sh erp/sales --recheck` → `exit=0`、判据全部 PASS、`📌 … gen/erp/sales/v1.0.0`。契约包首个 tag 还没打，这次重新生成不多出版本（R41 只约束已发布的契约包）。
- 4.10：没有超过 600 行的文件（最大 `write.go` 461 行），没有超过 150 行的函数（最长 `ListOrders` 91 行）。
- 4.12：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- 4.16 `make test-db-init ID=erp/sales`（12:53、13:07 各一次）：`{"msg":"迁移结束","direction":"up","schema":"erp_sales","outcome":"ok","version":4,"dirty":false}` ×2、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。
- 4.17 `make test` → `exit=0`，8 个包 ok；`go test ./... -race -count=1 -v`：76 个 PASS、0 FAIL、11 个 SKIP，全部是要真实依赖、由 `make test-cross ID=erp/sales` 跑的跨组件测试：`TestOpportunityWon_hopCount超限进DLQ且可重新投递`、`TestConfirmOrder_真实happy_path`、`TestConfirmOrder_真实库存不足`、`TestResolveAfterTimeout_真实查到RESERVED`、`TestReserve_真实超时能自我恢复不panic不出假结果`、`TestResolveAfterTimeout_查询也超时时写入对账队列`、`TestCompensateReserve_真实释放预留且不计失败次数`、`TestCompensateReserve_连续失败3次真建异常待办`、`TestCompensateReserve_未配置exceptionAssigneeSub时跳过建待办`、`TestHandleOpportunityWon_真实建单确认成功`、`TestHandleOpportunityWon_库存不足时不建单确认`。C7 的 `make verify` 里它们必须真的 PASS。
- 4.18 `component-check.sh`（C4 结束）：第 1–9 项 PASS，第 10 项（占位符）FAIL，符合预期。

**C4 审查结论（Task 的重构重点与控制者追加项）**

- 补偿路径（02-backend.md）：`Reserve` 超时先 `GetReservationStatus`（RESERVED 继续、未找到 503、CANCELLED 失败、查询也超时写对账队列 503）；补偿失败同一幂等键原地重试，连续 3 次 `SUSPENDED` + 异常待办（workflow 缺席或没配 assignee 时只记日志）；补偿用 `context.WithoutCancel`。符合。
- 赢单 payload 与 crm 契约（`components/crm/opportunity/contracts/events/opportunity.events.json`，只读）逐字段：`opportunity_id`、`customer_id`、`items[].product_id / quantity / quoted_unit_price`、`owner_id`、`dept_path`、`currency` 一一对应；`revision`（契约说与信封 version 同值）取信封的；`expected_close_date` 用不到、不取。`quantity` 走同一个 `validateQty`。另核对了 finance.credit.rejected.v1、infra.workflow.task.completed.v1、mdm.customer.created/updated.v1 的字段（updated.v1 的 `credit_limit` 非必填 → 上面 1316285 的修复）。
- `client/` 的超时与重试：每次调用各自 `context.WithTimeout(CallTimeout)`（5 秒）；用户路径上不自动重试（调用方带同一幂等键重试）；只有补偿重试。符合。
- 用户请求路径上的 `SystemClient`：`*System` 只在 `opportunity_won.go`（事件 handler）里用；`make gates` 的 `system-client-scan` 0 条违规。
- NaN 类：全部十进制输入路径——REST / gRPC 建单的 `qty`、试算的 `qty`、赢单事件的 `quantity`（三条都经 `findPriceTx` → `validateQty`）、客户事件的 `credit_limit`（`UpsertCustomerSnapshotCreditLimitTx`）。`quoted_unit_price` 不参与计算；finance 事件里的 `exposure` / `limit` 只拼进挂起原因的文字；上游 gRPC 响应里没有被本组件拿来计算的十进制字段；价格表的值来自本组件自己的迁移。四条路径都有红绿。
- R49：`contracts/sales.openapi.yaml` 没有声明任何 409，代码里也没有 `Aborted` / `AlreadyExists`；状态不对是 `FailedPrecondition`（→ 400）。没有要补的 409 测试。
- R51：见 011788b。
- 固定幂等键：测试里的写命令幂等键全部带 `uniqueSuffix` / 纳秒时间；赢单测试的键由每次不同的商机 id 派生。没有这个问题。

**C5 文档**：八份写满（d845965）。第一次 `make docs-check` 有 1 条警告：`⚠️ the code map names math/big.Rat, which does not exist`（AGENTS 代码地图第一张表里的行内代码被当成路径），改成不加反引号后：`component-check.sh` → `✅ component-check erp/sales：10 项全部 PASS`；`make docs-boundary` exit 0；`make docs-check ID=erp/sales` → `📋 Checked 2 files: 0 with errors, 0 warnings`，`exit=0`。

**C6 版本与门禁（13:00–13:05）**

- `make check-version test dag-check contract-check import-scan module-check` → `exit=0`：`✓ version=2.0.0（go.mod 主版本一致；HEAD 上没有 tag，或 2.0.0 与 v2.0.0 都在）`、8 个包 ok、`依赖：mdm/customer@2.0.0、mdm/product@2.0.0、erp/inventory@2.0.0、erp/finance@2.0.0、infra/workflow@2.0.0` / `✓ 依赖都是 @2.0.0，无自环`、`buf breaking --against '.git#tag=v1.0.26'`、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- `make test-db-init ID=erp/sales` → `✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。
- `go list -m all | grep brickKit/erp-sales` 恰好两行：`github.com/brickKit/erp-sales/v2`、`github.com/brickKit/erp-sales/gen/erp/sales v1.0.0 => ./gen/erp/sales`（Review Focus 1）。
- `project-lock.sh -- make gates`（exit 0，全文 `$S/gates.log`）：import / SystemClient / 裸路由 / 事件破坏 / data-scope-test / dependency-version 全部 `0 条违规`；`service-hostname-scan：0 条错误（1 条警告）`（`config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里`，预期）；`config-key-scan：0 条违规`（另有 frontend/standard 一个 1.x 组件 3 条 naming 警告）；`openapi-additive-scan：0 条违规（0 条跳过提示）`；`brickkit up --dry-run` 通过（erp/sales 还不在项目里，不在列表中）。
- ship 同判的发布前门禁（锁内）：`✓ config-key-scan（只看 components/erp/sales）：0 条违规` exit 0；`✓ openapi-additive-scan（只看 components/erp/sales）：0 条违规（0 条跳过提示）` exit 0。
- 发布说明 `$S/notes-2.0.0.md` 的"新增 / 修复"已先补好（C8 再核对一次 `--write` 有没有 ⚠️ 漂移）。

**C7 未开始**：上游 erp/inventory、erp/finance 的 `2.0.0` tag 还没推到远端，按 W2 规则停下问控制者。

### 现象

- 符合预期的：迁移工具与 go-v2 判据全部通过；SDK 一行迁移入口在测试库空跑 `outcome=ok`；组件门禁、项目门禁、发布前门禁全绿；文档第二次就过严格 lint。
- 不符合预期的：旧组件有多处真实 bug（游标 500、REST 不读时间窗口、BatchGetOrder 整批失败、金额走 float64、补偿只试一次、数量范围不校验、额度快照收 NaN 且 updated 事件把额度清零、缺默认仓库 panic、4xx 一律 ERROR）；`erp/finance` 是声明了却从不调用的依赖；`sales_order_reconciliation_queue` 只写不读。

### 卡点与绕过

1. **接手**：没有会话记录，靠提交信息草稿（`$S/msg-*.txt`）与工具日志还原；未提交的 stats 实现没有红的证据，用"返回空结果的桩"补跑红，再恢复实现（实现代码一行未改）。
2. **NaN 类的红**：当前代码已经拒绝 NaN，红只能在修复之前的提交上取证（d51e838 的临时 worktree），已删。
3. **P10 与事实不符（需要控制者确认）**：P10 写"sales `stats/summary` 不带视角参数（sales 的 List 没有）"，但 `GET /orders` 的 handler 早就读 `view=dept|mine`（前一位实现者已把它补进 REST 契约，6634a74），frontend-needs §2.4 也写"视角参数沿用 view=mine|dept，省略默认 dept"。按 P10 的原则"与同组件 List 端点完全一致"，`stats/summary` 带了 `view`（默认 dept），是二选一不是 OR，两个操作数都来自 `besdk.ScopeOf`。
4. 没有翻 brickKit 源码。读了本项目 `tools/be-sdk-go` 的 `scope.go`、`events.go`、`runtime.go`、`gin.go`、`client.go`（确认 ScopeOf 的 All 语义、Consume 不重投、MustString 会 panic、gRPC→HTTP 映射、gRPC 服务端没有建立 Claims 的拦截器）——项目内工具，不算知识缺口。

### V 项

- V-12（focus 与依赖容器共用 vars）：本组件是第一个有容器依赖的 focus，在 C7 的 `make verify … FOCUS=1` 里验，尚未开始。
- V-04 知识缺口：无。

### 结论

C1–C6 完成，停在 C7 之前。组件仓库 19 个提交就绪（未推送、未打 tag）；需要打契约包 tag `gen/erp/sales/v1.0.0`。C7 之前要重跑 1.1（erp/inventory、erp/finance 的 `2.0.0` / `v2.0.0` tag），C7 的 `make verify` 要让 11 条跨组件测试真的 PASS，并在 focus 里验 V-12。

### 反馈候选

- **gRPC 服务端不建立调用者的 Claims**（be-sdk-go，项目内）：`UserClient` 把 Authorization 透传过去，但服务端没有对应的拦截器，按数据范围过滤的 rpc（本组件的 `GetOrder` / `ListOrders`）经 gRPC 一律 ScopeOf panic → Internal。与 erp/inventory 记录里那条同源。→ 交控制者（项目内 SDK）。
- **部门路径为空 = 看得到全部**（be-sdk-go `ScopeOf` 的 `All: claims.DeptPath == ""`）：一个还没分配部门的用户在 dept 视图下看到全部订单。这是 SDK 的定义，不是本组件的 OR 操作数缺省；但对"别人的数据看不到"是个隐患，建议 SDK / iam 区分"根部门"与"未分配"。→ 交控制者。
- **`erp/finance` 依赖边**：声明了但没有任何同步调用（规划中的期间检查与额度对账从没实现），focus 闭包会无谓地带起 finance。保留还是去掉由控制者 / 后续设计定（写进了 docs/design.md 的未决问题）。

## 小结

- 完成：组件仓库提交（components/erp/sales，均未推送）——前一位实现者 9 个（01f2a29 … 6634a74），接手后 10 个：
  - 0bab8b7 feat: 新增 GET /stats/summary（仪表盘统计），按与订单列表相同的数据范围过滤
  - 9f48991 fix: 数量必须是大于 0 的十进制数且装得进 NUMERIC(18,6)，否则回 400
  - 1316285 fix: 客户额度快照只收非负十进制数；updated 事件没带额度时保留原值
  - 011788b fix: 调用方的错误与正常关闭不再记 ERROR；ERROR 只留给运维要处理的事
  - 1728d72 chore: Makefile / Dockerfile 按 v1 组件模板重写；种子脚本说明去掉历史
  - c8f8e80 fix: 缺 DEFAULT_WAREHOUSE_ID 时 module.New 返回 error 而不是 panic；空串也算缺
  - f7890c0 docs(code): 代码说明改写成原因本身，不再引用归档文档与历史
  - 15829f1 test: 测试注释改写成测的是什么、为什么，不再引用归档文档与历史
  - fc7f6c0 docs(contract): 改正 Order.order_no 注释里缺口的来源
  - d845965 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
- 父仓库：本 Task 没有写任何父仓库文件（除本记录与报告）；`registry/`、`brickkit.yaml`、`config/` 都没动（C7 才 integrate）。
- 需要控制者裁定的：P10 与事实不符时 `stats/summary` 带 `view`（卡点 3）；`erp/finance` 依赖边去留；上游是否已发布（C7 前）。
- 检查点：erp/sales 2.0.0 C1–C6 完成，组件 HEAD d845965，契约包待打 `gen/erp/sales/v1.0.0`。

## R60 / R54 / R55（以及 R62）：重做 C4–C6（2026-10-02 下午）

### 目标

在未发布的 2.0.0 上落实接手后的新裁定，版本号不变，重做 C4–C6，停在 C7 之前：
- R60：没分部门的人（token 的 `dept_path` 为空）org 维什么都不命中；be-sdk-go → v0.5.0；
- R54：`stats/summary` 的 `view=mine|dept` 二选一、不是 OR，写进 OpenAPI / BRICKKIT / design；
- R55：去掉对 `erp/finance` 的 required 依赖与死代码，`manifest-overrides.yaml` 加 `deps_drop` 后重跑 `migrate-manifest.py --write`；
- pin：`mdm/customer@2.0.1`（契约包 require 不变：`mdm-customer/gen` 远端最新仍是 `v1.0.6`）；`infra/workflow` 留在 `@2.0.0`（控制者在 C7 前改）；
- 控制者中途追加 R62：范围外的单张读取答 404（与不存在一样），命令仍答 403。

### 环境

brickKit v1.1.0；`be-sdk-go v0.5.0` 远端已有 tag；基础资源在跑（`be-postgres`）；没有起项目容器，本地模式 off。起点：组件 HEAD d845965。

### 步骤

**R60 红测试先行（SDK v0.4.0，实现未改）**，新增四个文件：`service/nodept_test.go`、`tcc/nodept_test.go`、`repo/nodept_test.go`、`http/view_test.go`。`go test … -run '无部门|根标记|留空报|不认识的view'` 的原文（`$S/red-r60.log`）：

```
view_test.go:18: GET /orders?view=Mine 应返回 400，实际 200
view_test.go:33: GET /stats/summary?view=Mine 应返回 400，实际 200
view_test.go:53: 无部门的人 GET /orders 应是 200 + 空列表，实际 code=200、50 张
nodept_test.go:17: dept 视图 ScopePrefix 留空应该是 ErrInvalidArgument，实际：<nil>
nodept_test.go:25: mine 视图 ScopeOwner 留空应该是 ErrInvalidArgument，实际：<nil>
nodept_test.go:33: dept 视图 ScopePrefix 留空应该是 ErrInvalidArgument，实际：<nil>
nodept_test.go:41: mine 视图 ScopeOwner 留空应该是 ErrInvalidArgument，实际：<nil>
nodept_test.go:48: 无部门的人 dept 视图应该看不到任何订单，实际 200 张（第一张 dept_path="" owner="u_nodept-1790945293283208431-1"）
nodept_test.go:74: 无部门的人 dept 视图的统计应该是 0 单 / 0.00，实际 4110 单（已确认 676）/ 119296.25
nodept_test.go:105: 无部门的人看别人的订单（dept_path="/1/12/"）应该是 ErrForbidden，实际：<nil>
nodept_test.go:123: 无部门的人确认别人的订单（dept_path="/1/12/"）应该是 ErrForbidden，实际：拨号 mdm/customer: besdk.UserClient: 依赖 mdm/customer 的地址未注入
nodept_test.go:49: 别的无部门的人不该看到这张单
--- PASS: TestListOrders_根标记斜杠看得到所有有部门的订单
```

"/" 根标记那条在 v0.4.0 上就是绿的（`"/"` 一直是普通前缀），是回归测试。

**旧用例单独提交（6a175cb）**：`repo/scope_test.go` 的 `{"根节点前缀天然命中全部", …, "", …, true}` 锁定的是 fail-open，删掉，换成"空前缀 org 一侧不命中 / 不命中 dept_path 为空的单 / owner 仍命中"与"/ 命中有部门的单、不命中空路径的单"。红：`InScope("", "u_someone_else") with order{DeptPath:"/1/99/" …} = true，期望 false`（两条）。

**只升 SDK、不改实现**（`go get be-sdk-go@v0.5.0` 后，`$S/red-r60-sdk050.log`）——这一步暴露了哨兵写进行里的后果：

```
nodept_test.go:35: 没有部门的人建的单 dept_path / dept_id 应该是空串，实际 "!no-dept" / "!no-dept"
nodept_test.go:48: 无部门的人 dept 视图应该看不到任何订单，实际 1 张（第一张 dept_path="!no-dept" owner="u_nodept_creator-1790945340951786256-1"）
nodept_test.go:74: 无部门的人 dept 视图的统计应该是 0 单 / 0.00，实际 1 单（已确认 0）/ 0.00
```

哨兵行被另一个无部门的人的 dept 前缀（同一个哨兵）命中。所以除了快照看 `HasDept`，仓储层 `CreateOrder` 再加一道守卫：`dept_path` 必须为空或以 `/` 开头（`checkDeptPathSnapshot`）。关掉这道守卫跑红：`nodept_test.go:55: dept_path="!no-dept" 应该是 ErrInvalidArgument，实际：<nil>`。两次红跑在 brickkit_test_db 留下了 `dept_path='!no-dept'` 的测试行（id 5302 等，共 2 行），已用 `docker exec be-postgres psql -U postgres -d brickkit_test_db` 删掉（`dept_path !~ '^/' and dept_path <> ''` 的订单与它的行），否则以后每次跑"无部门 dept 视图为空"都会红。

**实现（ef005d3）**：SDK v0.5.0；`tcc/create.go` 快照在 `!HasDept` 时写空串；`repo.checkViewScope`（List / Stats 选中视图的操作数为空 → `InvalidArgument`）；`Order.InScope` 空前缀 / 空 owner 那一侧不命中；`checkDeptPathSnapshot`；`http.parseView`（view 只认 dept / mine，其它 400——R54 本来就是二选一，前一位已实现，这里补的是"拼错的值不能悄悄当 dept"）。绿：94 PASS、0 FAIL、11 SKIP。

**R55（8f69719）**：`client.Finance()` 没有任何调用方，删掉；`go mod tidy` 去掉 `erp-finance/gen v1.0.10`。清单：`migrate-manifest.py` 不支持删依赖、也只会写 `@2.0.0`，于是给工具加了两个 overrides 字段（父仓库文件，未提交，见"卡点与绕过"）：`deps_drop: [erp/finance]`、`deps_pin: {mdm/customer: 2.0.1}`。`--write` 的 diff 正好是 `-erp/finance@2.0.0`、`mdm/customer@2.0.0 → @2.0.1`；`assembly.yaml：未改动`；`--check` → `✅ --check 全部为"无"`、`exit=0`（检查项"依赖不是 @2.0.0"改成"依赖不是 2.x 的确切版本"）。组件 `Makefile` 的 `dag-check` 同样改成接受 `@2.x.y`，手工验过 `@1.9.0`、`@2.0` 都失败。`--write` 打印 ⚠️"升级前必须做一节与重新生成的不同"：是我在发布说明这一节加了 R60 / R62 / view / finance 四条，是人改的，预期。

**顺手修的两处**：03d6823 日志里的旧键名 `exceptionAssigneeSub` → `EXCEPTION_ASSIGNEE_SUB`（`migrate-manifest.py` 的 ℹ️ 提示点出来的）；e9c49e5 `sales.proto` 注释说"四条强依赖边（含 erp/finance）"，R55 之后不成立，连同其余引用归档设计文档章节号的注释一起改写，`buf generate` 重新生成 gen（只有注释；契约包 tag v1.0.0 还没打，不产生新版本）。

**R62（e419f03，有意的行为变更）**：`service.GetOrder` 范围外返回 `fmt.Errorf("%w: order id=%s", repo.ErrNotFound, id)`，文案与不存在时一字不差；命令仍走 `checkOrderInScope` 答 403。测试随裁定改：`TestGetOrder_范围外ErrForbidden` → `…_范围外与不存在一样是ErrNotFound`（并断言文案相同），我上一步写的 `TestGetOrder_无部门的人看别人的订单是Forbidden` → `…_是NotFound`；新增 `http/single_test.go`（用 SDK 真实 engine，状态码经过它的错误映射）：范围外 GET 404、不存在 GET 404、范围外确认 403、本部门与负责人 GET 200。红：`service_test.go:106: 范围外应该是 ErrNotFound，实际：无权访问该订单`、`nodept_test.go:106: …实际：无权访问该订单`、`single_test.go:57: dept_path="/9/99/"：GET 范围外的订单应答 404，实际 403`。OpenAPI 只增：GET /orders/{id} 声明 404，确认 / 取消 / 发货声明 403 + 404，列表与统计声明 400，`dept_path` / `dept_id` 写明无部门时为空串。

**文档（d615e5c）**：四对文档中英同步写入 R60 / R54 / R55 / R62；第一次 `docs-check` 报 `⚠️ a placeholder (待补) is still in the text`（design.zh.md 我写的"不是待补的缺口"），改成"不是遗漏"后通过。

**C4–C6 重跑（全部绿）**：
- `go-v2.sh erp/sales --recheck` → `✅ go-v2.sh：判据全部 PASS`，`go list -m all` 里本仓库恰好两行，`📌 … gen/erp/sales/v1.0.0`；
- `component-check.sh erp/sales` → `✅ component-check erp/sales：10 项全部 PASS`；
- `make docs-check ID=erp/sales` → `📋 Checked 2 files: 0 with errors, 0 warnings`，exit 0；
- `make check-version test contract-check import-scan module-check dag-check` → exit 0：`✓ version=2.0.0…`、8 个包 ok、`buf breaking --against '.git#tag=v1.0.26'`、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`、`依赖：mdm/customer@2.0.1、mdm/product@2.0.0、erp/inventory@2.0.0、infra/workflow@2.0.0` / `✓ 依赖都钉在 2.x 的确切版本，无自环`；
- `make test-db-init ID=erp/sales`（拿锁）→ `✓ 迁移幂等`、`✓ brickkit_test_db 就绪`；
- `project-lock.sh -- make gates` → exit 0，九个 gate 零违规，`service-hostname-scan：0 条错误（0 条警告）`；
- ship 发布前门禁（锁内，`--only components/erp/sales`）：`openapi-additive-scan` 0 违规、`config-key-scan --strict` 0 违规。

### 现象

- 符合预期：SDK 升级本身让 org 维 fail-closed；改快照 + 守卫后全部绿。
- 不符合预期：只升 SDK 时哨兵被写进行里，又被另一个无部门的人的哨兵前缀命中——SDK 的"值层面 fail-closed"只在哨兵不进表时成立，写路径必须自己守。

### 卡点与绕过

1. **迁移工具不会删依赖、也不会钉非 2.0.0 的版本**：给 `dev/phase-06/tools/migrate-manifest.py` 加了 `deps_drop`（不带版本的 ID 列表，必须是现有依赖）与 `deps_pin`（`{ID: 2.x.y}`，保留 optional 等字段），`--check` 的依赖判据改成 `@2.x.y`；`manifest-overrides.yaml` 头注释、工具 README、`tests/run.sh`（§2.2 表的 sales 期望 + 新增一节 deps_drop / deps_pin 正反例）同步改。`BE_SCRATCH=<本会话 scratch> bash dev/phase-06/tools/tests/run.sh` → `━━━ 结果：489 通过，0 失败`（第一次跑 2 条失败：我新加的那节把 `$d` 改指 erp-sales，下一节默认它还是 mdm-customer；改用 `$ds` 后全绿）。都是父仓库文件，**没有提交**，交控制者（crm/opportunity 也要 `deps_pin: {mdm/customer: 2.0.1}`）。`manifest-overrides.yaml` 里原有的 sales description 改动与 infra/print 那一处都保留未动。
2. **红跑污染测试库**：见上，删掉了 2 行哨兵 / 非法路径的测试订单。
3. 没有翻 brickKit 源码；读了 be-sdk-go v0.5.0 的 `gin.go`（REST 测试要用 `NewGinEngine` 才有错误到状态码的映射）。

### 结论

R60 / R54 / R55 / R62 落实，C4–C6 全绿，组件 HEAD d615e5c（d845965 之后 7 个提交，未推送、未打 tag），版本仍是 2.0.0，契约包仍待打 `gen/erp/sales/v1.0.0`。停在 C7 之前：C7 前控制者要把 workflow 钉到 2.0.1（加进 `deps_pin` 后重跑 `--write`，并确认 erp/inventory 已发布）。

### 反馈候选

- be-sdk-go：`NoDeptPath` 的说明可以再强调一句"写路径上哨兵是 fail-open 的"——不写进行是对的，但写进去之后它会和下一个无部门调用者的前缀相等，测试里实际撞上了。可考虑在 SDK 里给一个 `ScopeFilter.DeptSnapshot()`（`HasDept` 为假时返回空串）供建单快照用。→ 交控制者。

## C7–C9：钉 workflow 2.0.1、接入、真机验证、交接（2026-10-02 傍晚，第三轮）

### 目标

上游已全部发布（mdm/customer 2.0.1、mdm/product 2.0.0、erp/inventory 2.0.0、infra/workflow 2.0.1、infra/authz 2.0.1；infra/iam-casdoor 已接入）。版本仍是 2.0.0。做：infra/workflow 钉 2.0.1；改正 `tcc/confirm.go` 异常待办 `assignee_dept_path` 的过时注释；演示库 `seed-clean`；C7 `make integrate` + `make verify ROUTE=/erp/sales/orders FOCUS=1 SEED=1 FORCE_BUILD=1`（11 条跨组件测试第一次真跑、V-12、Review Focus 2、根部门可见性、无部门反例）；C8 发布说明与提交；C9 记录。

### 环境

brickKit v1.1.0（env.sh 断言）；be-sdk-go v0.5.0；基础资源在跑；起点组件 HEAD d615e5c；本地模式 off、没有项目容器。项目锁期间别的工作线（crm/opportunity）也在排队跑 verify。

### 步骤

**1. 钉 workflow 2.0.1（1e5c378）**
- `manifest-overrides.yaml` 的 erp/sales：`deps_pin: {mdm/customer: 2.0.1, infra/workflow: 2.0.1}`；`migrate-manifest.py erp/sales --write` 的 diff 正好是 `-    - id: infra/workflow@2.0.0` / `+    - id: infra/workflow@2.0.1`（optional 不变）；`--check` → `✅ --check 全部为"无"`、`exit=0`。`--write` 照旧打印 ⚠️"升级前必须做一节与重新生成的不同"：差异只有第二轮手写的四条（R60 / R62 / view / finance），预期。
- 契约包：`git ls-remote --tags …/infra-workflow 'gen/*'` 最新是 `gen/infra/workflow/v1.0.4` → `go get …/gen/infra/workflow@v1.0.4`（v1.0.3 → v1.0.4）。其它上游契约包没升：inventory 远端最新仍是 v1.0.14、customer v1.0.6；product 有 v1.1.0，但本组件用不到新字段，按 brief 不升。
- 注释：建异常待办时 `AssigneeDeptPath: ""` 原注释写"不限部门"，与 workflow 2.0.x 的约定（BRICKKIT："留空的待办只有被指派人本人看得到"）相反，改成现状，代码不变。
- `go-v2.sh --recheck` → `✅ go-v2.sh：判据全部 PASS`、`📌 … gen/erp/sales/v1.0.0`；`go list -m all | grep brickKit/` 本仓库恰好两行（`…/erp-sales/v2`、`…/gen/erp/sales v1.0.0 => ./gen/erp/sales`）；`component-check` 10 项 PASS；`make check-version test contract-check import-scan module-check dag-check` exit 0（`依赖：mdm/customer@2.0.1、mdm/product@2.0.0、erp/inventory@2.0.0、infra/workflow@2.0.1`）；锁内 `make gates` exit 0、零违规。

**2. 演示库 seed-clean**
- `make -C components/erp/sales seed-clean` 第一次：`ERROR:  relation "command_idempotency" does not exist`，`make: *** [Makefile:128: seed-clean] Error 3`。原因：演示库 brickkit_db 里 `erp_sales` 只有 db-init 建的空 schema，迁移从没在这个库跑过，所以也没有 `dept_path=''` 的旧行要清。
- 修（a6201f6 的一部分）：DO 块开头 `to_regclass('erp_sales.command_idempotency') IS NULL` 就 NOTICE 后返回。重跑：`NOTICE:  erp_sales 还没有表（迁移没跑过），没有种子订单要删`、`✓ erp-sales 种子订单已清空…`、exit 0。

**3. 种子脚本的两处缺口（a6201f6）**——读 seed.sh 时发现，真机前修：
- 演示库 `erp_inventory.inventory_balances` 一行都没有，而 sales 的 `make seed` 不灌 inventory 的种子 → 确认 / 发货必然失败。改：依赖核对加 `erp/inventory`，在 mdm/product 之后调它的 seed（它给 mdm 的种子产品在 WH-EAST 各灌 200 件）。
- `confirm_order` / `ship_order` / `cancel_order` 原来 `curl -s … >/dev/null`：失败被吞，订单停在 DRAFT，脚本照样打 ✓。改成 `order_cmd`：状态码不是 2xx 就带响应体 `die`。

**4. C7 integrate**
- 第一次 `make integrate ID=erp/sales` → `✗ 第 3 步失败：config/erp-sales.yaml 还有 required 键需要人给值`，列出 `DEFAULT_WAREHOUSE_ID`。先核对 `select id, code from erp_inventory.warehouses` → `1|WH-EAST`、`2|WH-SOUTH`；`config-fill.py erp/sales --set 'DEFAULT_WAREHOUSE_ID=1' --set 'EXCEPTION_ASSIGNEE_SUB=u_ops_reviewer'` → `写了 2 个键`。
- 第二次 integrate → exit 0：`brickkit.yaml 里已是 erp/sales@2.0.0，跳过 add`；`✓ deploy.teardown.yaml 已与 deploy.yaml 一致`；`brickkit lint --strict erp/sales` → `📋 Checked 3 files: 0 with errors, 0 warnings`；`brickkit up --dry-run` 里 `erp/sales@2.0.0 starting (top-level)`，依赖图 `erp/sales@2.0.0 → mdm/customer@2.0.1 / mdm/product@2.0.0 / erp/inventory@2.0.0 / infra/workflow@2.0.1 (optional)`，没有 erp/finance；`✓ integrate erp/sales@2.0.0 完成`。
- `brickkit add` 的输出：`➕ Adding erp/sales@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`📝 Config skeletons: config/erp-sales.yaml`，7 个共享键自动写成 `$var:`。V-13：本组件加入的几行是纯新增，这次没看到注释被重排。

**5. 持锁 1（红）：真机发现信用额度快照的缺口**
- `project-lock.sh -- bash -c 'make verify … KEEP=1 FORCE_BUILD=1; iam / authz seed; red-repro.sh; brickkit down -f deploy.verify.yaml; rm -f deploy.verify.yaml'`（输出 `$S/c7/verify-red/`，闭包 `erp/inventory erp/sales infra/authz infra/iam-casdoor infra/workflow mdm/customer mdm/product`）。
- 推理：sales 只靠 `mdm.customer.*` 事件维护 `customer_snapshots`，SDK 的 Consume 是 NATS 核心订阅（`events.go`："当前实现走普通 NATS 核心订阅"），不重放；mdm/customer 的种子幂等重放不发事件。演示库里 15 个客户都早于 sales 存在 → 快照为空 → 额度 0 → 每张单确认都被拒。先写三条跨组件红测试（1aff3b2，`snapshot_refresh_test.go`），在这次 verify 的 test-cross 里跑红（原文）：
  ```
  snapshot_refresh_test.go:46: mdm/customer 给的额度是 100000.00，本单 300.00，应该确认成功，实际：参数不合法: customer_id=22 已用 0 + 本单 300.00 超过额度 0
  snapshot_refresh_test.go:82: mdm/customer 已把额度调到 1.00，本单 300.00 应该被拒，实际确认成功（用了快照里过时的 100000.00）
  snapshot_refresh_test.go:113: mdm/customer 给的额度是 100000.00，赢单转出的订单应该是 CONFIRMED，实际 "DRAFT"
  ```
- 同一次持锁里 REST 复现（`red-repro.sh`，复现订单用完即删）：
  ```
  客户 seed-customer-1 id=1（mdm 里额度 500000.00）；产品 seed-product-1 id=1
  erp_sales.customer_snapshots 里这个客户：0 行
  POST /orders → 200
  POST /orders/1/confirm → 400  {"error":"参数不合法: customer_id=1 已用 0 + 本单 100.00 超过额度 0"}
  ```
- 修（31b86d7）：第①步的 BatchGet 本来就拿到客户的 `credit_limit` 与 `version`，`tcc.checkCredit`（手工确认与赢单转单共用）先 `repo.RefreshCustomerSnapshot` 按 version 单调刷新快照（不盖掉事件带来的更新值；额度不合法时 WARN、沿用快照），再读快照判。新增 repo 测试 `TestRefreshCustomerSnapshot_按version单调且不收非法额度`。测试注释单独一个提交（15ce1fc，断言未动）；四对文档（3c82be5）：BRICKKIT 去掉"先起本组件再建客户，或者重放客户事件"（核心 NATS 根本重放不了），AGENTS 加一条易错点，跨组件测试 11 → 14 条。按"重构许可"，原因写进了 docs/design.md 的确认链一节；对外行为变化（额度按当前值判）写进发布说明的"修复"。

**6. 持锁 2（绿）：`make verify ID=erp/sales ROUTE=/erp/sales/orders FOCUS=1 SEED=1 FORCE_BUILD=1 KEEP=1`**（组件 HEAD 3c82be5 之后构建；输出 `$S/c7/verify/`）

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build erp/sales | PASS |  | build.log |
| 镜像 erp-sales:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（7 个） | PASS |  | migration-*.log |
| erp-sales-2-0-0 running (healthy)（容器服务 erp-sales-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /erp/sales/orders 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /erp/sales/orders 带 token → 200 | PASS |  | http.log |
| make -C components/erp/sales seed | PASS |  | seed.log |
| make test-cross ID=erp/sales | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8084/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down | SKIP | KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml |  |

- seed.log：`✓ 探测到 mdm-product 种子数据，已给 12 个真实产品各灌 200 件库存（WH-EAST）`、`✓ 订单（dev.superuser）：2(CONFIRMED) 3(SHIPPED) 4(CANCELLED)`、`✓ 订单（dev.sales.east/华东）：5(DRAFT) 6(CONFIRMED)`。
- 同一持锁里 `make test-cross ID=erp/sales ARGS='-v -count=1'`（`$S/c7/test-cross-v.log`）：`PASS 总数 110，FAIL 0，SKIP 0`。11 条原有跨组件测试逐条 `--- PASS`：`TestOpportunityWon_hopCount超限进DLQ且可重新投递`、`TestConfirmOrder_真实happy_path`、`TestConfirmOrder_真实库存不足`、`TestResolveAfterTimeout_真实查到RESERVED`、`TestReserve_真实超时能自我恢复不panic不出假结果`、`TestResolveAfterTimeout_查询也超时时写入对账队列`、`TestCompensateReserve_真实释放预留且不计失败次数`、`TestCompensateReserve_连续失败3次真建异常待办`、`TestCompensateReserve_未配置exceptionAssigneeSub时跳过建待办`、`TestHandleOpportunityWon_真实建单确认成功`、`TestHandleOpportunityWon_库存不足时不建单确认`；新增 3 条也是 PASS。
- 同一持锁里的手工核对（`hold2-checks.sh`）失败：`✗ dev.superuser 换应用 JWT 失败`。原因见"卡点与绕过 1"，改在持锁 3 做。
- 同一持锁里的 V-12 深度探针（`v12-probe.sh`，原文 `$S/c7/v12-probe.log`），见下面"V 项"。

**7. 持锁 3：容器形态的手工核对**（`make verify … KEEP=1`，不带 FOCUS，镜像就是持锁 2 构建的那个；输出 `$S/c7/verify-checks/`，汇总表全部 PASS / 写明原因的 SKIP、test-cross 再 PASS 一次；然后 `hold2-checks.sh`，`$S/c7/hold3-checks.log`）
- **A. 根部门可见性**（dev.superuser 在 `/1/`）：
  ```
  GET /erp/sales/orders → 200
    共 5 张；按 (dept_path, owner_id, status) 计数：
      ('/1/', 'e88c4f5a-…', 'CANCELLED') 1
      ('/1/', 'e88c4f5a-…', 'CONFIRMED') 1
      ('/1/', 'e88c4f5a-…', 'SHIPPED') 1
      ('/1/2/', '4f269a9f-…', 'CONFIRMED') 1
      ('/1/2/', '4f269a9f-…', 'DRAFT') 1
  GET /erp/sales/stats/summary → 200：order_count=5, confirmed_count=3, total_amount='1700.00'
  ```
  `4f269a9f-…` 是 dev.sales.east 的 sub：华东（`/1/2/`）的种子订单经根前缀可见，端到端成立。
- **B. 反例**（成本低，直接做）：authz `POST /api/admin/users/<dev.finance.viewer>/roles` 临时授 `dev_sales_rep`（带 10 分钟后的 `expires_at`），等 18 秒刷新 bundle：
  ```
  dev.finance.viewer 的 token：dept_path=''（只打印这一项 claim）
  GET /erp/sales/orders（默认 dept 视图）→ 200：0 张
  GET /erp/sales/stats/summary → 200：order_count=0
  GET /erp/sales/orders/2（dev.superuser 的单）→ 404：{"error":"not found: order id=2"}
  GET /erp/sales/orders/999999999（不存在）→ 404：{"error":"not found: order id=999999999"}
  撤销 dev.finance.viewer 的 dev_sales_rep → 200
  ```
  范围外与不存在的文案一字不差（R62）；事后 `user_roles` 里只剩 `dev_finance_viewer`。
- **C. Review Focus 2**（`EXCEPTION_ASSIGNEE_SUB=u_ops_reviewer`，本组件唯一一个有默认值的自有键，默认 `""`）：superuser 建单（order 8）；装两个只针对这张单的触发器：`erp_sales.sales_orders` 上拦"变成 CONFIRMED"（FinalizeConfirm 失败 → 补偿），`erp_inventory.inventory_reservations` 上拦"变成 CANCELLED"（补偿连续失败）；确认：
  ```
  确认 → 500：{"error":"更新 sales_orders: ERROR: rf2 故障注入：拦下 sales_orders_2026_10_01 的 CONFIRMED 状态变更 (SQLSTATE P0001)"}
  订单：SUSPENDED compensation_attempts=3 suspended_reason=补偿连续失败 3 次，需要人工介入
   type    | status  |  assignee_sub  | assignee_dept_path |               title
   EXCEPTION | PENDING | u_ops_reviewer |                    | 订单 8 补偿连续失败，需要人工介入
  ```
  容器日志：`WARN 补偿失败：CancelReservation 出错 … attempts:1/2/3`、`ERROR 补偿连续失败，订单已挂起，需要人工释放预留`、`INFO 已建异常待办`。配置值从行为上生效。收拾：删触发器，用 inventory 自己的 `CancelReservation`（grpcurl）释放预留 → `RESERVATION_STATUS_CANCELLED`，删探针订单与待办。事后 `pg_trigger` 里没有 `rf2%`，演示库只剩种子订单 2–6。
- 收尾：`brickkit down -f deploy.verify.yaml` → 0；`没有本项目组件容器`；`Local mode: off`；项目根没有 `deploy.verify.yaml` / `deploy.local.yaml`。

**8. C8**
- 发布说明 `$S/notes-2.0.0.md`：升级前必须做的依赖一行改成钉 `mdm/customer@2.0.1`、`mdm/product@2.0.0`、`erp/inventory@2.0.0`、`infra/workflow@2.0.1`（optional）；"修复"加信用额度快照刷新、本地演示数据两条。⚠️ 漂移：差异仍只是手写的那几条。
- 交接前重跑（HEAD 3c82be5）：锁内 `make gates` exit 0，十个 gate 零违规、`service-hostname-scan：0 条错误（0 条警告）`；`go-v2.sh --recheck` 全部 PASS；`component-check` 10 项 PASS；`migrate-manifest.py --check` 全部为"无"；ship 同判的发布前门禁（`be-acceptance gate … --only components/erp/sales`）：`openapi-additive-scan` 0 违规 exit 0、`config-key-scan --strict` 0 违规 exit 0。
- 组件工作区干净，C8 没有另外要提交的东西；镜像在最后一个提交之后构建（8.6 满足）。

### 现象

- 符合预期：钉版本、integrate、迁移、健康、鉴权、种子、跨组件测试（第一次真跑，全部 PASS）、focus、根前缀可见性、无部门反例、异常待办派给配置的人。
- 不符合预期：信用额度快照只靠不重放的事件，装进已有客户的项目后整条确认链失效（已修）；`seed-clean` 在空 schema 上报错（已修）；种子脚本不灌库存、吞掉确认失败（已修）；`FOCUS=1 KEEP=1` 之后手工步骤找不到 authz / iam。

### 卡点与绕过

1. **`FOCUS=1 KEEP=1` 留下的不是完整闭包**：verify 的 focus 一步跑 `brickkit up --focus erp/sales`，focus 只起本组件的依赖（`⬜ infra/authz@2.0.1 not starting (outside the focus)`、`⬜ infra/iam-casdoor@2.0.0 not starting (outside the focus)`），focus 结束后 verify 不把 deploy.verify.yaml 的闭包重新拉起来。所以 KEEP=1 之后、同一持锁里的手工步骤里，iam 换 token 失败（`✗ dev.superuser 换应用 JWT 失败`）。绕过：要用 token 的手工步骤放到一次不带 FOCUS 的 `KEEP=1` verify 之后（持锁 3）。→ 反馈候选 1。
2. **V-12 的"本机进程能不能连到依赖"**，verify 的 focus 一步只验 `/healthz`。另写探针：自己开本地模式、照 verify 的规则改写 vars、停掉 sales 容器让事件只由宿主机进程消费，再发一条 `crm.opportunity.won.v1`（scratch 里的小 Go 程序 `natspub`，带 SDK 的信封 Header）。
3. 没翻 brickKit 源码；读了本项目 `tools/be-sdk-go/events.go`（Consume 是核心订阅、信封 Header 名）与 `infra/scripts/verify-component.sh`（focus 的 vars 改写、KEEP 的收尾），都是项目内文件，不算知识缺口。

### V 项

- **V-12（focus 的本机进程与依赖容器共用 vars）：成立，Linux 原生 Docker 上够用。**
  - verify 的 focus 一步：`focus：宿主机 http://localhost:8084/healthz → 200` PASS。
  - 探针里 `deploy.local.yaml` 的 vars 改写（原文 diff 的 vars 部分）：
    ```
    > vars:
    >   PG_HOST: 172.17.0.1
    >   NATS_URL: nats://172.17.0.1:4222
    >   S3_URL: http://172.17.0.1:9000
    ```
    host-gateway IP `172.17.0.1`，`改写的 vars：PG_HOST, NATS_URL, S3_URL`。
  - 宿主机进程（`/proc/<监听 8084 的 pid>/environ`，只取地址类的键）：`MDM_CUSTOMER_ENDPOINT=http://localhost:18080`、`MDM_PRODUCT_ENDPOINT=http://localhost:18082`、`ERP_INVENTORY_ENDPOINT=http://localhost:18086`、`INFRA_WORKFLOW_ENDPOINT=http://localhost:18201`（brickKit 自己把 `*_ENDPOINT` 改写成宿主机映射端口）、`PG_HOST=172.17.0.1`、`NATS_URL=nats://172.17.0.1:4222`、`AUTHZ_BUNDLE_URL=http://infra-authz-2-0-1:8223/authz/bundle`、`IAM_JWKS_URL=http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json`。
  - 宿主机 TCP：customer / product / inventory / workflow、NATS、postgres 都 `通`；authz、iam `不通`（容器服务名，focus 里也没起它们：受保护路由在 focus 下验不了，与 7.4 的说明一致）。
  - 真实调用：发 `crm.opportunity.won.v1`（商机 `v12-probe-1790952575`）→ 宿主机进程日志 `"msg":"商机赢单自动建单确认成功","opportunity_id":"v12-probe-1790952575","order_id":"7"`，库里 `7 CONFIRMED reservation_id=30`：本机进程经 NATS 收到事件、连 postgres 落库、以系统身份 gRPC 调了 customer / product / inventory（`Endpoint(dep, "grpc")` 换算出的端口也通）。workflow 只验了 TCP（这条路径成功，没有建待办）。探针订单已释放预留（`RESERVATION_STATUS_CANCELLED`）并删掉。
- **V-13**：`brickkit add erp/sales` 这次只新增行，没有看到注释被重排。
- **V-04 知识缺口**：无。

### 结论

C7–C9 完成。组件 HEAD 3c82be5（d615e5c 之后 6 个提交，未推送、未打 tag），版本 2.0.0，契约包要打 `gen/erp/sales/v1.0.0`。verify（FOCUS=1 SEED=1 FORCE_BUILD=1）全部 PASS，14 条跨组件测试全部 PASS，V-12 成立，Review Focus 2 从行为上确认。真机发现并修复了信用额度快照的启动缺口（先红后绿）。

### 反馈候选

1. **verify 的 `FOCUS=1 KEEP=1`**（项目工具，交控制者）：focus 之后保留下来的环境缺 authz / iam（以及组件自己的容器），同一持锁里要 token 的手工步骤全部失败。建议 KEEP=1 时 focus 结束后再 `brickkit up -f deploy.verify.yaml` 把闭包拉回来，或者在 component-loop 7.2 第 7 项写明"要 token 的手工步骤不要和 FOCUS=1 同一次"。
2. **事件维护的快照普遍有启动缺口**（项目内，交控制者）：`besdk.Consume` 是核心订阅、不重放，组件晚于上游装进项目、或停机期间，快照永远缺行或过时。sales 已经改成在确认时用同步 BatchGet 的结果按 version 刷新。别的组件里只靠事件维护的副本要逐个查一遍。已核对的一个：erp/inventory 的 `product_tracking_snapshots`（追踪方式，BRICKKIT："kept from `mdm/product` events"）同样只靠 `mdm.product.*` 事件维护，而 inventory 不调用任何组件，没有可以顺手刷新的同步读。它装进已有产品的项目后，这些产品没有追踪方式副本，按批次 / 序列号追踪的产品会被当成什么、要 inventory 那边判断。
3. **`EXCEPTION_ASSIGNEE_SUB=u_ops_reviewer` 在演示环境里没有对应的人**：Casdoor 种子里没有这个 sub，待办又是空部门路径（只有被指派人本人看得到）。所以演示环境里没人看得到、批得了补偿失败的异常待办。要演示这条路径，可以给 iam / authz 种一个运维复核用户，再把它的 sub 配进 `config/erp-sales.yaml`（sub 是 Casdoor 的内部 ID，每套环境不同）。
4. `docs/en/03-seed-data.md`（项目文档，不在本工作线范围）：erp/sales 那一行可以补一句"种子会先灌 erp/inventory 的库存"。

## 小结（第三轮）

- 组件提交（components/erp/sales，未推送）：
  - 1e5c378 chore: infra/workflow 钉到已发布的 2.0.1，契约包 require 升到远端最新的 v1.0.4；改正异常待办 assignee_dept_path 的注释
  - 1aff3b2 test: 额度快照不能只靠事件——客户比本组件先有、或停机期间改过额度时，确认要按 mdm/customer 的当前额度判
  - 31b86d7 fix: 确认订单先用 BatchGet 拿到的客户按 version 刷新额度快照再判额度（手工确认与赢单转单两条路径）
  - 15ce1fc test: seedCustomerSnapshot 的注释改成现状（确认链会用 BatchGet 刷新快照；断言未动）
  - a6201f6 fix(seed): make seed 先灌 erp/inventory 的库存；确认 / 发货 / 取消不是 2xx 就大声失败；seed-clean 在没有表的库上什么都不做
  - 3c82be5 docs: 信用额度在确认时按 mdm/customer 的回答刷新，写进四对文档；跨组件测试 11 → 14 条
- 父仓库（未提交，交控制者按路径提交）：`dev/phase-06/tools/manifest-overrides.yaml`（sales 的 `deps_pin` 加 `infra/workflow: 2.0.1`）、integrate 写的 `config/erp-sales.yaml`（新文件）以及 `brickkit.yaml` / `deploy.yaml` / `deploy.teardown.yaml` / `AGENTS.md` 里 erp/sales 的行，本记录与报告。
- 检查点：erp/sales 2.0.0 可以发布；ship 时要打的 tag：`gen/erp/sales/v1.0.0`、`2.0.0`、`v2.0.0`。

## R63：库身份来自配置（2026-10-02 晚，第四轮）

### 目标

按 R63 把 erp/sales 的库身份全部改成来自配置：`SET LOCAL ROLE` 的角色取 `PG_USER`（不再是 `PG_SCHEMA + "_rw"`），迁移里不写角色名 / schema 名，BRICKKIT「Before you deploy」写成通用要求，用一条 L2 测试证明非默认 schema + 任意名字的角色能迁移、读写。顺带按重构许可检查设计。版本仍是 2.0.0，不推送、不打 tag。

### 环境

起点组件 HEAD 3c82be5；brickKit v1.1.0（env.sh 断言）；be-sdk-go v0.5.0；PostgreSQL 16.15（be-postgres）；本地模式 off、开始时没有项目容器。测试 DSN 用 `eval "$(bash dev/phase-06/tools/env.sh erp/sales)"` 拼出。common.md 中途新加了 .env 规则（不许 source）；在那之前最初几次 `go test` 用过 `set -a; . .env`，命令没有输出任何值，之后一律改用 env.sh。

### 步骤

**1. 找写死的身份**：`grep -rnI '_rw\|erp_sales\|OWNER\|SET ROLE\|search_path\|PG_USER\|PG_SCHEMA'`（排除 gen/、.git/）。
- 产品代码里只有两处：`backend/module/module.go:107` 的 `role: schema + "_rw"`；`001_create_sales.up.sql:54/95`、`002_create_outbox_inbox.up.sql:40/65` 四条 `ALTER TABLE … OWNER TO erp_sales_rw`。
- `scripts/seed-clean.sh` 写死了 `brickkit_db` 与 `erp_sales`（`SET search_path TO erp_sales`、`to_regclass('erp_sales.command_idempotency')`）。`seed.sh` 不连库。
- `backend/internal/tcc` 等包的非测试代码里没有。测试里约 60 处 `repo.New(db, "erp_sales_rw", "erp_sales")` / `erp_sales.<表>` 是 brickkit_test_db（test-db-init 开出的）的夹具名，不是推导，保留（见结论）。
- `config_test.go` 断言 `role == "erp_sales_x_rw"`，锁的正是被推翻的规则。

**2. 红（1a1f1aa）**：`backend/module/identity_test.go`。
- 在 brickkit_test_db 现建 `r63_sales_<随机>`、登录角色 `r63_owner_<随机>`（故意不叫 `<schema>_rw`，`GRANT USAGE, CREATE ON SCHEMA`），另建 `NOINHERIT` 的外壳角色 `r63_shell_<随机>`（`GRANT owner TO shell`）。
- 以 owner 角色 `migrate.Run` 两遍，查 schema 里没有不属于它的对象。
- `besdk.NewShellRuntime` + `module.New`，经 `mod.RegisterGRPC` 的 gRPC 面 `CreateOrder` + `GetOrder`（mdm/customer、mdm/product 用测试进程里的假 gRPC 服务），独立运行（以 owner 登录）与外壳（以 NOINHERIT 外壳角色登录）各一遍；再用管理连接确认订单落在配置的 schema。
- 结束时删 schema 与两个角色。原文：
```
identity_test.go:53: 以登录角色 r63_owner_e7db970765ca 迁移进 schema r63_sales_e7db970765ca 失败（第 1 次）：迁移 up 失败（schema r63_sales_e7db970765ca）：migration failed: must be able to SET ROLE "erp_sales_rw" …
(details: ERROR: must be able to SET ROLE "erp_sales_rw" (SQLSTATE 42501))
--- FAIL: TestNew_库身份只来自配置_非默认schema与任意名字的登录角色 (0.14s)
```
跑完 `pg_roles` / `pg_namespace` 里 `r63_%` 为 0。

**3. 错的测试单独改（6e621ab）**：`config_test.go` 配 `PG_USER=sales_app`，期望 `role=sales_app`。红：`期望 {schema:erp_sales_x role:sales_app …}，实际 {schema:erp_sales_x role:erp_sales_x_rw …}`。

**4. 新的红（e848c17）**：`PG_USER` 缺失 / 空 / `Sales-App`、`PG_SCHEMA` 为 `erp.sales` / 空时 `readConfig` 应返回 error（`besdk.WithTx` 只收 `^[a-z][a-z0-9_]*$`，以前要到第一个请求才在每个事务里报错）。红：`map[DEFAULT_WAREHOUSE_ID:1]：应返回 error，实际 {schema:erp_sales role:erp_sales_rw …}` 等五条。

**5. 迁移零效果删除（9158956）**：删掉四条 `OWNER TO`，002 的注释改成"迁移以 PG_USER 运行，表本来就属于它"。证明：
- `make test-db-init ID=erp/sales` 连跑两次 exit 0，每次 `"迁移结束","schema":"erp_sales","outcome":"ok","version":4,"dirty":false` ×2、`✓ 迁移幂等`。
- 属主逐行对比（`pg_class` 里 erp_sales 下 r/p/S/v/m，改前快照与改后 diff）：
```
== brickkit_test_db: diff before/after
(identical, 35 objects)
erp_sales_rw|35
== brickkit_db: diff before/after
(identical, 43 objects)
erp_sales_rw|43
```
- 测试往下走到 module 一步才红：`建单（写）失败：rpc error: code = Internal desc = 定价失败: SET LOCAL ROLE r63_sales_ec66c9e9e210_rw: ERROR: role "r63_sales_ec66c9e9e210_rw" does not exist (SQLSTATE 22023)`。

**6. 绿（520c93b）**：`readConfig` 的 role 取 `PG_USER`，两个名字按 WithTx 的正则校验，不合法时报错并点名键。
```
--- PASS: TestReadConfig_按configSchema的键名读 (0.00s)
--- PASS: TestReadConfig_缺默认仓库时返回错误而不是panic (0.00s)
--- PASS: TestReadConfig_PG_USER与PG_SCHEMA缺失或不合法时返回错误 (0.00s)
--- PASS: TestNew_库身份只来自配置_非默认schema与任意名字的登录角色 (0.54s)
    --- PASS: …/独立运行_连接池以PG_USER登录 (0.04s)
    --- PASS: …/进外壳_连接池以外壳角色登录_事务里切到PG_USER (0.04s)
```

**7. 设计发现：初始分区是写死的日期（fcb6e7a 红 → 9720627 绿）**。
- 001 / 002 的初始分区从 2026-09 起写死（周分区到 2026-10-05、月分区到 2026-11）。新库装在这些日期之后，当周 / 当月没有分区，后台维护第一轮之前的写入报 `no partition of relation`。
- 新测试：新 schema 迁移完就要有当前与下一个周期的分区。红：`identity_test.go:339: 迁移完缺这些分区（今天 2026-10-02）：[event_outbox_2026_10_05 event_inbox_2026_10_05]`。
- 新迁移 005 用 DO 块按执行当天补齐与维护任务相同的窗口（月 4 个、周 5 个，同一套命名，先 `to_regclass`），不写 schema / 角色名；down 不删分区。绿：`--- PASS: TestMigrate_新schema迁移完就有当前与下一个周期的分区`。
- `make test-db-init ID=erp/sales` 再连跑两次：`version 5、dirty false`、`✓ 迁移幂等`。
- 真实影响：brickkit_test_db 的周分区只到 2026-10-05（测试从不跑周分区维护），下周一起写 outbox 的测试都会失败。005 补了 8 张，原有 35 个对象一行没变：
```
> event_inbox_2026_10_05|r|erp_sales_rw   （另有 _10_12 / _10_19 / _10_26）
> event_outbox_2026_10_05|r|erp_sales_rw  （另有 _10_12 / _10_19 / _10_26）
```
- brickkit_db 的分区早由运行中的维护任务建好；verify 迁到 version 5 之后属主对比 `diff` 无输出（43 个对象，全部 `erp_sales_rw`，`schema_migrations_erp_sales` = `5|f`）。

**8. seed-clean（da512e5）**：库与 schema 取自 `config/erp-sales.yaml`（`$var:` 从 `config/vars.yaml` 取，缺省用 component.yaml 默认），SQL 用 `SET search_path TO :"schema"`、裸表名。
- 先在 brickkit_test_db 演练（那里没有 `seed-order-*` 行）：`-v schema=r63_nonexistent` → `NOTICE:  schema r63_nonexistent 还没有表（迁移没跑过），没有种子订单要删`，exit 0；`erp_sales` exit 0。
- 再锁内真跑一次演示库：`🔒 project lock acquired …`、`NOTICE:  删除订单: {2,3,4,5,6}`、`✓ erp-sales 种子订单已清空…`；之后 verify 的 SEED=1 重新灌回。

**9. 文档（0bf5879）**：
- BRICKKIT 两语「Before you deploy」改成通用要求：一个 schema、一个能连库、有 USAGE+CREATE 并跑迁移的登录角色，名字随意；必须是小写标识符；外壳登录角色须是 PG_USER 的成员、默认 INHERIT。配置表 `PG_USER` 不再要求 `<PG_SCHEMA>_rw`；`make seed` 补上 erp/inventory。
- design 两语：「库身份是配置」一段（原因）、005 的原因、未决问题加一行（StartOutboxPump 不切角色）。
- AGENTS 两语：代码地图、设计取舍、两条易错点；Makefile 说明。
- `make docs-check ID=erp/sales` → `📋 Checked 3 files: 0 with errors, 0 warnings`。

**10. 门禁（HEAD 0bf5879）**：
- `component-check.sh erp/sales` → `✅ component-check erp/sales：10 项全部 PASS`。
- `go-v2.sh erp/sales --recheck` → `✅ go-v2.sh：判据全部 PASS`，`📌 第 8.3 步需要打的契约包 tag：gen/erp/sales/v1.0.0`。
- `make check-version test contract-check import-scan module-check dag-check docs-check` exit 0：8 个包全 `ok`；`✓ 无组件间 import`；`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`；`依赖：mdm/customer@2.0.1、mdm/product@2.0.0、erp/inventory@2.0.0、infra/workflow@2.0.1`。`go test ./... -v` 的 SKIP 仍是 14 条（真依赖的跨组件测试）。
- `migrate-manifest.py erp/sales --check` → `✅ --check 全部为"无"`。
- 锁内 `make gates` exit 0：import / SystemClient / 裸路由 / 事件破坏 / data-scope-test / dependency-version 全部 `0 条违规`，`service-hostname-scan：0 条错误（0 条警告）`，`config-key-scan：0 条违规`（frontend/standard 1.x 的 3 条只警告），`openapi-additive-scan：0 条违规`。
- 发布前门禁：`openapi-additive-scan（只看 components/erp/sales）：0 条违规` exit 0；`config-key-scan … --strict：0 条违规` exit 0。

**11. 真机**：`make verify ID=erp/sales ROUTE=/erp/sales/orders FORCE_BUILD=1 SEED=1`（加 SEED=1 是因为第 8 步清掉了演示订单）：

| 项 | 结果 |
|---|---|
| brickkit build erp/sales（--force） | PASS |
| 镜像 erp-sales:2.0.0：sh + wget、/app/component.yaml | PASS |
| brickkit up -f deploy.verify.yaml | PASS |
| 迁移容器 Exited (0)（7 个）；sales：`"迁移结束","schema":"erp_sales","outcome":"ok","version":5,"dirty":false` | PASS |
| erp-sales-2-0-0 running (healthy) | PASS |
| GET /healthz → 200 | PASS |
| GET /erp/sales/orders 不带 token → 401 | PASS |
| GET /erp/sales/orders 带 token → 200 | PASS |
| make -C components/erp/sales seed | PASS |
| make test-cross ID=erp/sales | PASS（8 个包全 ok） |
| brickkit up --focus erp/sales | SKIP（没设 FOCUS=1，brief 没要） |
| brickkit down，docker ps 里没有本项目容器 | PASS |

收尾：本地模式 off。根目录那份 deploy.verify.yaml 是之后 crm/opportunity 工作线的 verify（18:03 起持锁）写的，不是本轮留下的。

### 现象

- 符合预期：两处迁移相关的红出现在不同位置（先迁移、后 module），各自修掉；零效果删除对已有库无影响；verify 全 PASS。
- 不符合预期：迁移里写死日期的初始分区会在新库上过期，brickkit_test_db 已经只差三天就没有当周的 outbox 分区（已修）。
- 不符合预期：写本记录时根分区满了（`/dev/nvme1n1p5 239G … 100%`），第一次追加只写了一半；已截回原来的 385 行再重写。`docker system df`：Build Cache 111.5GB（可回收 12.96GB）、Images 22.59GB（可回收 15.67GB）。没有清理，交控制者。

### 卡点与绕过

1. .env 读法见「环境」。
2. 磁盘满见「现象」。
3. 没翻 brickKit 源码；读了 be-sdk-go v0.5.0 的 `migrate/migrate.go`（DSN 的 search_path 与状态表）、`tx.go`、`outbox.go`、`shell.go`（`NewShellRuntime`）、`client.go`，都是项目依赖，不算知识缺口。

### 结论

R63 在 erp/sales 落地：角色来自 `PG_USER`，迁移不含任何角色 / schema 名，seed-clean 读配置，BRICKKIT 写成通用要求。非默认 schema 加无关名字角色的 L2 测试（独立运行与 NOINHERIT 外壳角色两种）全绿。重构许可下多修一处：迁移 005 让新库在任何日期迁移完就能写。测试代码里的 `erp_sales_rw` / `erp_sales` 字面量保留：它们是 test-db-init 开出的测试库夹具名，不是推导；名字不同的情形由 identity_test 覆盖。组件 HEAD 0bf5879，版本 2.0.0，未推送、未打 tag。

### 反馈候选

1. **be-sdk-go `StartOutboxPump` 不切角色**（交控制者）：它以连接池的登录角色直接 `UPDATE <schema>.event_outbox`。外壳里登录角色是外壳自己，所以外壳角色必须 INHERIT 地是每个成员 `PG_USER` 的成员；在 NOINHERIT 的外壳角色下业务事务正常，Outbox 推送却会 permission denied。建议 SDK 让推送也收 role、每批走 `WithTx`。本组件已在 BRICKKIT 写明这条要求。
2. **项目工具仍按 `<schema>_rw` 推角色**（父仓库，交控制者）：`infra/scripts/test-db-init.sh` 第 ② 步 `PG_USER="${schema}_rw"`，①b 把属主转给 `${schema}_rw`。`registry/schemas.tsv` 已有 role 列，可以直接取那一列。
3. **别的组件可能有同样写死日期的初始分区**：本组件 002 的旧注释写着"同其它组件的 002 迁移"，各组件的 002（outbox / inbox 周分区）大概率都只覆盖到 2026-10 初；brickkit_test_db 里这些组件的周分区下周一起可能缺。值得每条工作线按 R63 顺手查。
4. `besdk.WithTx` 的标识符正则不收大写、连字符等 PostgreSQL 合法的角色名；本组件在 New 时就报清楚，但"名字随意"实际是"小写标识符随意"。
5. 根分区满（见「现象」）：几条并行工作线的 `brickkit build --force` 在攒构建缓存。

## 修复轮：发布前修 I1 / I2 / I3（部分）/ M1 / M2 与 .env 写法（2026-10-02 深夜，第五轮）

### 目标

按 task-18-review.md 修发布前的问题：I1（同一个键重放成功过的确认 / 发货答 400）、I2（财务拒绝信用挂起的订单永远占着库存）、I3 只改正 design 的未决问题一行、M1（发布说明去掉内部裁定编号）、M2（gRPC 没有用户身份时的答复与文档）、AGENTS 不再让人 source .env。组件仍是未发布的 2.0.0，起点 HEAD 0bf5879。

### 环境

起点：没有项目容器，本地模式 off，根分区 114G 可用（50%）。TEST_PG_DSN 由 env.sh 给出，没读 .env。

### 步骤

**1. I1（b9ff2da 红 → a5b40b9）**：新增 `backend/module/harness_test.go`（经 module.New 装起本组件，mdm 与 erp/inventory 是测试进程里计数的假 gRPC 服务，键每次运行唯一）、`replay_test.go`、`tcc/won_replay_test.go`。红（HEAD 0bf5879 的实现）：
```
replay_test.go:28: 同一个键重放确认应返回第一次的结果，实际：rpc error: code = FailedPrecondition desc = 订单不是草稿状态: order id=10518 status=CONFIRMED
replay_test.go:53: 同一个键重放发货应返回第一次的结果，实际：rpc error: code = FailedPrecondition desc = 订单不是草稿状态: order id=10519 status=SHIPPED，只有 CONFIRMED 才能发货
replay_test.go:101: 同一个键重放建单应返回第一次的结果，实际：rpc error: code = InvalidArgument desc = 参数不合法: 客户不可用：customer_id=C-harness-1790959042117163571 status=CUSTOMER_STATUS_DISABLED
replay_test.go:126: 确认用过的键拿去发货：期望 InvalidArgument，实际 <nil>
won_replay_test.go:57: 同一商机再来一次不该开异常待办，实际开了 1 条
```
取消的重放实现前就绿（CANCELLED 本来就放行）。修法：`repo.ReplayCommand` 在建单、确认、取消、发货与赢单两步的最前面查 `command_idempotency`，成功过就返回第一次的订单；键绑定命令与订单（同 infra/workflow），不符答 InvalidArgument；建单键对应的订单不在调用者范围内也按键冲突答 400；Finalize* 里并发声明失败那条路径用同一套规则。全部其它写命令都查过：取消原来不受这个顺序问题影响，建单的问题是重放前先做远程校验，一并改掉。

**2. I2（9dae568 红 → 23f92bd 测试改用补偿挂起 → d62a3b0）**：`consumer/credit_rejected_test.go`（假 mdm / inventory / workflow，handler 在 WithTx 里跑，与 besdk.Consume 一样）。红：
```
credit_rejected_test.go:44: 挂起订单应开一条异常待办，实际 0 条
credit_rejected_test.go:52: 挂起且占着预留的订单应能取消，实际：订单已经是终态，不能再流转: order id=10827 status=SUSPENDED 不能取消
credit_rejected_test.go:72: 已发货的单库存已出库，不该被挂起，实际 SUSPENDED
```
裁定：SHIPPED 不挂起（库存已出，挂起拦不住什么、也没有出口），记 Warn 并开待办。修法：CancelOrder 接受信用挂起的单（先释放预留再取消），补偿挂起的仍拒绝（按 `suspended_reason` 区分，FinalizeCancel 锁行后再判）；SuspendOrderTx 返回 SuspendOutcome；handler 挂起时、已发货时都给订单负责人开异常待办（`tcc/credit_rejected.go`，幂等键 `credit-rejected:<订单>:exception-task`，尽力而为）。service/loglevel_test 那条"挂起的单不能取消"原来借的是任意 reason 的挂起单，单独一个提交改用补偿挂起（断言未动）。design 两语写下两种挂起的出路、已发货不挂起、新的未决问题（被拒的单不能恢复）。

**3. I3（d998d78）**：design 两语未决问题那一行改写：只有同一个命令带同一个键重试才找得回；放弃 / 换新键、进程停在④与⑤之间、赢单路径找不回；库存预留不过期；对账队列没人读。

**4. M2（f0bd544 红 → de7c490）**：`module/grpc_identity_test.go`，服务端拦截器模拟 SDK 的 recovery。红（六个 rpc 各一条，原文相同）：
```
grpc_identity_test.go:52: CreateOrder 没有调用者身份：期望 Unauthenticated，实际 rpc error: code = Internal desc = panic: besdk.ScopeOf: ctx 里没有 Claims——只能在 RequirePermission 已经验过签的请求路径上调用；Start()/事件 handler 里查数据请用 SystemClient，不经过这里
```
修法同 erp/finance 的 `requireUser`；CalculatePriceDryRun / BatchGetOrder / GetOrderStatus 不变。design、BRICKKIT（两语）改成全部六个 rpc。

**5. .env（4937ee5）**：AGENTS 两语的构建与测试改成 iam-casdoor 的写法（密码是 .env 里的 POSTGRES_PASSWORD，不要 source，DSN 写占位）；migrate-idempotent 那行也写占位。没写 env.sh：它在 dev/ 下，组件文档不该引用项目的开发工具。

**6. M1**：`$S/notes-2.0.0.md` 去掉（R63）（R60）（R62）（R55）与"R60，fail-open"，"本项目"改成"BrickEnterprise 项目"；修复一节补上 I1、I2、M2 三条（含两处行为变更）。改前留底 `notes-2.0.0.md.before-fix-round`。

**7. 门禁（HEAD 4937ee5）**：
- `component-check.sh erp/sales` → `✅ component-check erp/sales：10 项全部 PASS`
- `make docs-check ID=erp/sales` → `📋 Checked 3 files: 0 with errors, 0 warnings`
- `make check-version test contract-check import-scan module-check dag-check` exit 0：8 个包 ok；`buf breaking --against '.git#tag=v1.0.26'`；`✓ 无组件间 import`；`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`；`✓ 依赖都钉在 2.x 的确切版本，无自环`。`go test ./... -v` 的 SKIP 仍是 14 条。
- `go-v2.sh erp/sales --recheck` → `✅ go-v2.sh：判据全部 PASS`，契约包 tag 仍是 `gen/erp/sales/v1.0.0`（gen 没动）
- `migrate-manifest.py erp/sales --check` → `✅ --check 全部为"无"`
- 锁内 `make gates` exit 0：import / SystemClient / 裸路由 / 事件破坏 / data-scope-test / dependency-version / config-key / openapi-additive 全部 `0 条违规`，`service-hostname-scan：0 条错误（0 条警告）`

**8. 真机**（一次持锁：`make verify ID=erp/sales ROUTE=/erp/sales/orders FORCE_BUILD=1 SEED=1 KEEP=1` → 第二次 `make -C components/erp/sales seed` → `brickkit down -f deploy.verify.yaml`，输出 `$S/fix/verify/`）：

| 检查项 | 结果 | 原因 |
|---|---|---|
| brickkit build erp/sales | PASS | |
| 镜像 erp-sales:2.0.0：sh + wget、/app/component.yaml | PASS | |
| brickkit up -f deploy.verify.yaml | PASS | |
| 迁移容器 Exited (0)（7 个） | PASS | |
| erp-sales-2-0-0 running (healthy) | PASS | |
| GET /healthz → 200 | PASS | |
| GET /erp/sales/orders 不带 token → 401/503 | PASS | 实际 401 |
| GET /erp/sales/orders 带 token → 200 | PASS | |
| make -C components/erp/sales seed | PASS | |
| make test-cross ID=erp/sales | PASS | 8 个包 ok |
| brickkit up --focus erp/sales | SKIP | 没设 FOCUS=1 |
| brickkit down | SKIP | KEEP=1，锁内手工收尾 |
| 第二次 make seed（I1） | PASS | exit 0，订单 id 与第一次相同 |
| 锁内 brickkit down -f deploy.verify.yaml | PASS | exit 0；docker ps 只剩 be-* 基础资源；deploy.verify.yaml 已删；Local mode: off |

两次 seed 的输出都是：
```
✓ 订单（dev.superuser）：9(CONFIRMED) 10(SHIPPED) 11(CANCELLED)
✓ 订单（dev.sales.east/华东）：12(DRAFT) 13(CONFIRMED)
```
确认 / 发货 / 取消用的是同样的固定键，第二次全部走重放，订单号不变。

### 现象

符合预期：五处红都出在审查指出的位置，修完全绿；第二次 `make seed` 不再死在确认。test-cross 这次也是不带 -v 跑的（只看到 8 个 ok，没数 PASS / SKIP 行，同 M9）。

### 卡点与绕过

无。没读 brickKit 源码；读了 be-sdk-go v0.5.0 的 `client.go`（SystemClient 只要注入地址）、`scope.go`（ScopeOf 取不到 Claims 就 panic），以及 infra/workflow 的 `repo/idempotency.go`（键与命令不符的规则），都是项目依赖或同项目组件。

### 结论

I1、I2、M2 修好并有红绿证据；I3 只改正了文档，清理任务留到设计轮；M1 发布说明已改；AGENTS 不再让人 source .env。组件 HEAD 4937ee5，版本仍是 2.0.0，未推送、未打 tag。

### 反馈候选

1. be-sdk-go 没有不 panic 的 Claims 读取函数：erp/finance 与本组件都靠 recover `besdk.ScopeOf` 判"有没有用户身份"。建议 SDK 提供 `ClaimsFrom(ctx) (Claims, bool)`。
2. I3 的清理（扫对账队列与陈旧草稿，或库存侧预留过期）要在设计轮定是 sales 做还是 inventory 做。
